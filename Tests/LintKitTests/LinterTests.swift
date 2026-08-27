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

/// **A skill's folder name has to be a legal name, and has to survive being typed into a command.**
///
/// The published rule for a skill's name is lowercase letters, digits and hyphens, no hyphen at either
/// end, no doubled hyphen, at most 64 characters. Nothing here checked the name at all, so a folder
/// called `-demo` was reported as having no problems — and the command this tool prints for it,
/// `skillet run -demo`, fails when pasted because the word is read as a switch.
///
/// The **folder** name is what is checked, not the name written inside SKILL.md, because the folder name
/// is what gets pasted into commands and because the two are allowed to disagree here: the reproduction
/// was a folder called `-demo` whose SKILL.md said `name: demo`, which passed everything.
@Suite("SKILL-L012 — the folder name is a legal, typable skill name")
struct NameShapeTests {
    private func source(name: String) -> SkillSource {
        SkillSource(name: name, frontmatter: SkillFrontmatter(name: "demo", description: "ok"),
                    body: "# demo\n", evals: nil, evalsPresent: false)
    }

    private func nameFindings(_ name: String) -> [Diagnostic] {
        Linter().lint(source(name: name)).filter { $0.id == "SKILL-L012" }
    }

    /// The measured break: this exact name made the tool print a command that fails when pasted.
    @Test("A name starting with a hyphen is an error, because commands naming it do not run",
          arguments: ["-demo", "-x", "--demo"])
    func leadingHyphenIsAnError(name: String) throws {
        let found = try #require(nameFindings(name).first { $0.tier == .error })
        #expect(found.message.contains(name))
    }

    /// Off-spec but harmless to anything you can run, so it must not stop a build.
    @Test("Names that break the published rule without breaking a command only warn",
          arguments: ["Demo", "my_skill", "demo-", "a--b", String(repeating: "a", count: 65)])
    func otherViolationsWarn(name: String) {
        let found = nameFindings(name)
        #expect(!found.isEmpty, "'\(name)' breaks the published name rule and should be reported")
        #expect(found.allSatisfy { $0.tier == .warn },
                "'\(name)' runs fine, so an error tier would fail a build over a name that works")
    }

    @Test("Ordinary names are reported as nothing at all",
          arguments: ["demo", "tidy-notes", "review-pull-request", "a1", String(repeating: "a", count: 64)])
    func legalNamesAreSilent(name: String) {
        #expect(nameFindings(name).isEmpty)
    }

    /// One rename should settle the whole name, rather than fixing one fault and being told the next.
    @Test("Several faults in one name are reported together")
    func faultsReportedTogether() throws {
        let found = try #require(nameFindings("Bad--Name-").first { $0.tier == .warn })
        #expect(found.message.contains("lowercase"))
        #expect(found.message.contains("end with a hyphen"))
        #expect(found.message.contains("two hyphens in a row"))
    }

    @Test("Suppressing the rule silences it, which is what keeps a dash-named skill usable")
    func suppressible() {
        let quiet = Linter().lint(source(name: "-demo"), config: .init(disable: ["SKILL-L012"]))
        #expect(quiet.allSatisfy { $0.id != "SKILL-L012" })
    }
}
