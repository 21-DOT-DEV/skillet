import Testing
import Foundation
import EDDCore
@testable import ScoreKit

/// Behavior + calibration for the deterministic scorers. Samples are small and targeted, seeded with the
/// real predecessor slop words/patterns (per the plan): a clean sample stays silent, a sloppy sample
/// fires at the expected rule/level. Runs end-to-end through `ScoreRunner` over temp files.
@Suite("ScoreKit — scorers, disposition, calibration")
struct ScoreKitTests {
    private func run(_ files: [String: String],
                     config: SkilletConfig.Scorers = SkilletConfig.Scorers()) -> ScoreRunner.Output {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("score-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {}   // caller-independent temp; left for the OS to reap
        for (name, content) in files {
            let url = dir.appendingPathComponent(name)
            try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data(content.utf8).write(to: url)
        }
        return ScoreRunner(toolVersion: "0.0.0").run(path: dir, config: config)
    }
    private func findings(_ out: ScoreRunner.Output, _ rule: String) -> [ScoreFinding] {
        out.report.findings.filter { $0.ruleId == rule }
    }

    // MARK: calibration — clean stays silent, sloppy fires

    @Test("S001 slop-vocabulary: clean prose is silent; sloppy prose fires with a located message")
    func s001() {
        #expect(findings(run(["a.md": "The parser reads the file and returns a value cleanly here."]), "SKILL-S001").isEmpty)
        let out = run(["a.md": "This delve into the intricate tapestry shows a crucial testament indeed."])
        let f = findings(out, "SKILL-S001")
        #expect(!f.isEmpty)
        #expect(f.allSatisfy { $0.level == .error || $0.level == .warning })
        #expect(f.contains { $0.message.contains("delve") })
    }

    @Test("S002 puffery fires on marketing language")
    func s002() {
        #expect(findings(run(["a.md": "The function parses input and writes output."]), "SKILL-S002").isEmpty)
        #expect(!findings(run(["a.md": "This world-class library works seamlessly and stands as a lifeline."]), "SKILL-S002").isEmpty)
    }

    @Test("S003 em-dash: a 0-em-dash file stays SILENT (target scale, not penalizing absence); over-use fires")
    func s003() {
        #expect(findings(run(["a.md": "A clean technical sentence with no em dashes at all here."]), "SKILL-S003").isEmpty)
        #expect(!findings(run(["a.md": "One—two—three—four dashes pack this short line densely now."]), "SKILL-S003").isEmpty)
    }

    @Test("S004 rule-of-three: rhetorical triple fires; technical + inline-code triples are skipped")
    func s004() {
        #expect(!findings(run(["a.md": "It is fast, cheap, and reliable."]), "SKILL-S004").isEmpty)          // rhetorical
        #expect(findings(run(["a.md": "The variants P2WPKH, P2WSH, and P2SH all work."]), "SKILL-S004").isEmpty)  // technical skip
        #expect(findings(run(["a.md": "Compose `foo`, `bar`, and `baz` together."]), "SKILL-S004").isEmpty)       // inline-code skip
    }

    @Test("S005 knowledge-cutoff: three disclaimer phrases fire as a raw count")
    func s005() {
        #expect(findings(run(["a.md": "The API returns a value synchronously."]), "SKILL-S005").isEmpty)
        let out = run(["a.md": "As of my last update, my training data is limited, and I cannot verify this."])
        #expect(!findings(out, "SKILL-S005").isEmpty)
    }

    @Test("S006 not-x-but-y is DEFAULT-OFF; enabling it via config makes the contrast fire")
    func s006() {
        let text = "It's not about speed, it's about correctness."
        #expect(findings(run(["a.md": text]), "SKILL-S006").isEmpty)                                          // off by default
        let enabled = SkilletConfig.Scorers(enable: ["SKILL-S006"])
        #expect(!findings(run(["a.md": text], config: enabled), "SKILL-S006").isEmpty)                        // on via enable
    }

    // MARK: config

    @Test("vocab.exempt removes a whole word-list entry (so the exempt term stops firing)")
    func exempt() {
        let text = "This tapestry and tapestry and tapestry is everywhere."
        #expect(!findings(run(["a.md": text]), "SKILL-S001").isEmpty)
        let exempted = SkilletConfig.Scorers(vocab: .init(exempt: ["tapestry"]))
        let out = run(["a.md": text], config: exempted)
        #expect(!out.report.findings.contains { $0.message.contains("tapestry") })
    }

    @Test("vendored_prefixes skips a folder at any depth (gitignore-style), never a look-alike file")
    func vendored() {
        let files = ["Vendored/x.md": "delve delve delve here.", "sub/Vendored/y.md": "delve delve delve here.",
                     "VendoredFoo.md": "delve delve delve here."]
        let config = SkilletConfig.Scorers(vendoredPrefixes: ["Vendored/"])
        let out = run(files, config: config)
        // Only VendoredFoo.md (a look-alike file, not a Vendored folder) is scored.
        let paths = Set(out.report.findings.compactMap { finding -> String? in
            if case let .region(file, _, _, _, _, _, _) = finding.location { return file } else { return nil } })
        #expect(paths == ["VendoredFoo.md"])
    }

    @Test("disable turns a default-on scorer off")
    func disable() {
        let text = "This delve into the intricate tapestry shows a crucial testament."
        #expect(!findings(run(["a.md": text]), "SKILL-S001").isEmpty)
        #expect(findings(run(["a.md": text], config: SkilletConfig.Scorers(disable: ["SKILL-S001"])), "SKILL-S001").isEmpty)
    }

    // MARK: disposition

    @Test("A malformed .sarif is an S007 error (exit stays 0); a valid one is silent and un-scored")
    func sarifValidity() {
        #expect(!findings(run(["out.sarif": "{ not json"]), "SKILL-S007").isEmpty)
        #expect(!findings(run(["out.sarif": #"{"version":"2.0.0","runs":[]}"#]), "SKILL-S007").isEmpty)   // wrong version
        let valid = run(["out.sarif": #"{"version":"2.1.0","runs":[]}"#])
        #expect(findings(valid, "SKILL-S007").isEmpty)
        #expect(findings(valid, "SKILL-S001").isEmpty)   // excluded from density scoring
    }

    @Test("A binary file is silently skipped (counted, no finding); an oversized file is an S000 note")
    func skipAndOversize() {
        let binary = run(["b.dat": "\u{0}binary data with a NUL"])   // NUL ⇒ decodeText returns nil ⇒ binary
        #expect(binary.report.summary.filesSkipped >= 1)
        #expect(findings(binary, "SKILL-S000").isEmpty)

        let big = String(repeating: "word ", count: 230_000)   // > 1 MiB
        let over = run(["big.md": big])
        #expect(!findings(over, "SKILL-S000").isEmpty)
        #expect(over.report.summary.filesUnreadable >= 1)
    }

    @Test("Findings are sorted deterministically by (path, offset, rule)")
    func ordering() {
        let out = run(["z.md": "delve here.", "a.md": "delve tapestry crucial here."])
        let paths = out.report.findings.compactMap { f -> String? in
            if case let .region(file, _, _, _, _, _, _) = f.location { return file } else { return nil } }
        #expect(paths == paths.sorted())   // a.md before z.md
    }

    // MARK: region math

    @Test("Region offsets count Unicode scalars, not UTF-16 units or bytes (multi-byte safe)")
    func scalarRegion() {
        // 😀 (one scalar) + space + "delve": 'delve' starts at scalar offset 2, column 3.
        let out = run(["e.md": "😀 delve delve delve."])
        let f = findings(out, "SKILL-S001").first
        guard case let .region(_, startLine, startColumn, _, _, charOffset, charLength)? = f?.location else {
            Issue.record("expected a region finding"); return
        }
        #expect(startLine == 1)
        #expect(charOffset == 2)      // 😀=0, space=1, d=2
        #expect(startColumn == 3)     // 1-based
        #expect(charLength == 5)      // "delve"
    }

    @Test("Region math counts scalars for combining marks + CJK, and treats CRLF as one line break")
    func regionMath() {
        // Combining mark: "é" as e + U+0301 = TWO scalars before the space.
        let combining = "e\u{301} delve"
        let r1 = SarifRegionCompute.region(for: combining.range(of: "delve")!, in: combining)
        #expect(r1.charOffset == 3 && r1.startColumn == 4)   // e(0) ́(1) space(2) d(3)

        // CJK: each ideograph is one scalar.
        let cjk = "日本語 delve"
        let r2 = SarifRegionCompute.region(for: cjk.range(of: "delve")!, in: cjk)
        #expect(r2.charOffset == 4 && r2.startColumn == 5)   // 日(0)本(1)語(2)space(3)d(4)

        // CRLF: the \r is part of the ending, so the match is on line 2, column 1.
        let crlf = "top\r\ndelve"
        let r3 = SarifRegionCompute.region(for: crlf.range(of: "delve")!, in: crlf)
        #expect(r3.startLine == 2 && r3.startColumn == 1)
    }

    @Test("A hard-linked input is refused with an S000 disclosure, never scored — closes T1 (round 17)")
    func hardLinkedInputIsRefusedNotScored() throws {
        // Sloppy content that WOULD fire S001 if a hard link's inode reached a density scorer.
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("score-out-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let secret = outside.appendingPathComponent("secret.md")
        try Data("This delve into the intricate tapestry is a crucial testament indeed.".utf8).write(to: secret)

        let scoreDir = FileManager.default.temporaryDirectory.appendingPathComponent("score-in-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scoreDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scoreDir) }
        try FileManager.default.linkItem(at: secret, to: scoreDir.appendingPathComponent("hard.md"))   // hard link across the boundary

        let out = ScoreRunner(toolVersion: "0.0.0").run(path: scoreDir, config: SkilletConfig.Scorers())
        // T1: the hard-linked inode's content must NOT influence the score…
        #expect(!out.report.findings.contains { $0.ruleId == "SKILL-S001" })
        // …it is disclosed as not-scored (S000) with the shared hard-link reason.
        #expect(out.report.findings.contains { $0.ruleId == "SKILL-S000" && $0.message.contains("hard link") })
    }
}
