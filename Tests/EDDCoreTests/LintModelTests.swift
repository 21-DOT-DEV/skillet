import Testing
import Foundation
import EDDCore

@Suite("Lint models")
struct LintModelTests {
    // Decoded via JSON here because EDDCore is YAML-free; the real YAML decode is covered in
    // ConfigYAMLTests. `SkilletConfig.Lint`'s snake_case CodingKeys match the JSON keys directly.
    @Test("SkilletConfig.Lint: an absent block uses the shipped defaults")
    func lintDefaults() throws {
        let lint = try JSONDecoder().decode(SkilletConfig.Lint.self, from: Data("{}".utf8))
        #expect(lint.disable == [])
        #expect(lint.bodyWarnLines == 500)
        #expect(lint.bodyErrorLines == 1000)
    }

    @Test("SkilletConfig.Lint: a partial block keeps the other defaults")
    func lintPartial() throws {
        let json = #"{"body_warn_lines":120,"disable":["SKILL-L003"]}"#
        let lint = try JSONDecoder().decode(SkilletConfig.Lint.self, from: Data(json.utf8))
        #expect(lint.disable == ["SKILL-L003"])
        #expect(lint.bodyWarnLines == 120)
        #expect(lint.bodyErrorLines == 1000)   // untouched key keeps its default
    }

    @Test("SkilletConfig.Lint round-trips through encode/decode (custom decode ↔ synthesized encode)")
    func lintEncodeRoundTrip() throws {
        let original = SkilletConfig.Lint(disable: ["SKILL-L003"], bodyWarnLines: 120, bodyErrorLines: 800)
        let decoded = try JSONDecoder().decode(SkilletConfig.Lint.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("LintReport tallies tiers and stamps skillet.lint/1 with snake_case fields")
    func reportSchemaAndCounts() throws {
        let report = LintReport(diagnostics: [
            Diagnostic(id: "SKILL-L001", tier: .error, skill: "a", message: "m", fixHint: "f"),
            Diagnostic(id: "SKILL-L009", tier: .warn, skill: "a", message: "m", fixHint: "f"),
            Diagnostic(id: "SKILL-L003", tier: .error, skill: "b", message: "m", fixHint: "f")
        ])
        #expect(report.errors == 2)
        #expect(report.warnings == 1)
        let json = try SkilletJSON.encode(report)
        #expect(json.contains(#""schema":"skillet.lint/1""#))
        #expect(json.contains(#""fix_hint":"f""#))   // convertToSnakeCase applied to payload fields
    }
}
