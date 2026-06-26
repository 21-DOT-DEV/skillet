import Testing
import Foundation
import EDDCore
import LintKit

@Suite("Linter rules")
struct LinterTests {
    private func source(
        name: String = "demo",
        description: String? = "ok",
        body: String = "# demo\n",
        evals: EvalsFile? = nil,
        evalsPresent: Bool? = nil
    ) -> SkillSource {
        SkillSource(
            name: name,
            frontmatter: SkillFrontmatter(name: name, description: description),
            body: body,
            evals: evals,
            evalsPresent: evalsPresent ?? (evals != nil)
        )
    }

    private func evals(_ count: Int) -> EvalsFile {
        let cases = (0..<count).map { JSONValue.object(["id": .number(Double($0)), "prompt": .string("p\($0)")]) }
        return EvalsFile(raw: .object(["skill_name": .string("demo"), "evals": .array(cases)]))
    }

    // MARK: L001

    @Test("L001: a >1024 code-point description errors; ≤1024 is clean")
    func l001Length() {
        let long = String(repeating: "a", count: 1025)
        #expect(Linter().lint(source(description: long)).contains { $0.id == "SKILL-L001" && $0.tier == .error })

        let ok = String(repeating: "a", count: 1024)
        #expect(!Linter().lint(source(description: ok)).contains { $0.id == "SKILL-L001" })
    }

    @Test("L001 counts code points, not grapheme clusters (combining marks can't hide length)")
    func l001CodePoints() {
        // 600 × (base-e + combining acute) = 600 grapheme clusters but 1200 code points → must flag.
        let sneaky = String(repeating: "e\u{0301}", count: 600)
        #expect(sneaky.count <= 1024)                  // grapheme clusters slip under the limit...
        #expect(sneaky.unicodeScalars.count > 1024)    // ...while code points exceed it
        #expect(Linter().lint(source(description: sneaky)).contains { $0.id == "SKILL-L001" && $0.tier == .error })
    }

    @Test("L001: missing/unparseable frontmatter errors")
    func l001MissingFrontmatter() {
        let src = SkillSource(name: "demo", frontmatter: nil, body: "x\n", evals: evals(3), evalsPresent: true)
        #expect(Linter().lint(src).contains { $0.id == "SKILL-L001" && $0.tier == .error })
    }

    // MARK: L003

    @Test("L003: body budget — ok / warn / error")
    func l003Budget() {
        #expect(!Linter().lint(source(body: "a\nb\nc\n")).contains { $0.id == "SKILL-L003" })
        #expect(Linter().lint(source(body: String(repeating: "x\n", count: 600))).contains { $0.id == "SKILL-L003" && $0.tier == .warn })
        #expect(Linter().lint(source(body: String(repeating: "x\n", count: 1100))).contains { $0.id == "SKILL-L003" && $0.tier == .error })
    }

    @Test("L003: fenced code blocks don't count toward the body budget")
    func l003ExcludesCode() {
        let body = "intro\n```\n" + String(repeating: "code\n", count: 700) + "```\noutro\n"
        #expect(!Linter().lint(source(body: body)).contains { $0.id == "SKILL-L003" })
    }

    @Test("L003: custom thresholds drive the tiers")
    func l003CustomThresholds() {
        let config = SkilletConfig.Lint(bodyWarnLines: 50, bodyErrorLines: 100)
        let diagnostics = Linter().lint(source(body: String(repeating: "x\n", count: 60)), config: config)
        #expect(diagnostics.contains { $0.id == "SKILL-L003" && $0.tier == .warn })
    }

    @Test("L003: a terminal newline is a line terminator, not an extra blank line")
    func l003TrailingNewline() {
        // Exactly the warn threshold (500) stays clean; 501 warns. 1000 stays warn; 1001 errors.
        #expect(!Linter().lint(source(body: String(repeating: "x\n", count: 500))).contains { $0.id == "SKILL-L003" })
        #expect(Linter().lint(source(body: String(repeating: "x\n", count: 501))).contains { $0.id == "SKILL-L003" && $0.tier == .warn })
        #expect(!Linter().lint(source(body: String(repeating: "x\n", count: 1000))).contains { $0.id == "SKILL-L003" && $0.tier == .error })
        #expect(Linter().lint(source(body: String(repeating: "x\n", count: 1001))).contains { $0.id == "SKILL-L003" && $0.tier == .error })
    }

    @Test("L003: mismatched fences and fence-like content lines don't mis-toggle (CommonMark)")
    func l003FenceEdges() {
        // A `~~~` line inside a ```-opened block is content (it doesn't close the block); the ``` closes it.
        let body = "intro\n```\n" + String(repeating: "~~~ still code\n", count: 700) + "```\noutro\n"
        #expect(!Linter().lint(source(body: body)).contains { $0.id == "SKILL-L003" })
    }

    @Test("L003: an unclosed fence runs to EOF — later lines don't count (CommonMark, conscious)")
    func l003UnclosedFence() {
        let body = "intro\n```\n" + String(repeating: "code\n", count: 700)   // no closing fence
        #expect(!Linter().lint(source(body: body)).contains { $0.id == "SKILL-L003" })
    }

    // MARK: L009

    @Test("L009: missing evals errors; <3 warns; ≥3 is clean")
    func l009Evals() {
        #expect(Linter().lint(source(evals: nil)).contains { $0.id == "SKILL-L009" && $0.tier == .error })
        #expect(Linter().lint(source(evals: evals(2))).contains { $0.id == "SKILL-L009" && $0.tier == .warn })
        #expect(!Linter().lint(source(evals: evals(3))).contains { $0.id == "SKILL-L009" })
    }

    @Test("L009: a present-but-unparseable evals.json errors with a distinct message")
    func l009Corrupt() {
        let diagnostics = Linter().lint(source(evals: nil, evalsPresent: true))
        #expect(diagnostics.contains { $0.id == "SKILL-L009" && $0.tier == .error && $0.message.contains("not valid JSON") })
        #expect(!diagnostics.contains { $0.message == "no evals.json found" })
    }

    // MARK: config

    @Test("disable suppresses rules by id")
    func disableRules() {
        let src = source(description: String(repeating: "a", count: 2000), evals: nil)
        let config = SkilletConfig.Lint(disable: ["SKILL-L001", "SKILL-L009"])
        #expect(Linter().lint(src, config: config).isEmpty)
    }
}
