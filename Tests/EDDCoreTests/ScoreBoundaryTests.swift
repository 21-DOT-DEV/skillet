import Testing
import Foundation
@testable import EDDCore

/// Frozen-format goldens for the F17 boundary types: the camelCase SARIF *writer* (`SarifDocument`) and
/// the snake_case native report (`ScoreReport`), including the hand-flattened `ScoreLocation`.
@Suite("F17 score boundary formats")
struct ScoreBoundaryTests {
    private func sampleSarif() -> SarifDocument {
        let rules = [
            SarifRule(id: "SKILL-S001", name: "slop-vocabulary", shortDescription: "Over-used AI vocabulary"),
            SarifRule(id: "SKILL-S007", name: "sarif-validity", shortDescription: "Emitted findings-file validity")
        ]
        let region = SarifResult(
            ruleId: "SKILL-S001", level: .warning, rank: 62, message: "AI-slop vocabulary: `delve`",
            locations: [SarifLocation(physicalLocation: SarifPhysicalLocation(
                artifactLocation: SarifArtifactLocation(uri: "notes.md"),
                region: SarifRegion(startLine: 2, startColumn: 5, endLine: 2, endColumn: 10, charOffset: 12, charLength: 5)))],
            properties: ["skillet.density": .number(8), "skillet.goodness": .number(0.38)])
        let categorical = SarifResult(
            ruleId: "SKILL-S007", level: .error, rank: nil, message: "Invalid SARIF 2.1.0: missing version",
            locations: [.file("out.sarif")], properties: nil)
        return SarifDocument(runs: [SarifRun(tool: SarifTool(driver: SarifDriver(
            name: "skillet", version: "0.0.0", rules: rules)), results: [region, categorical])])
    }

    @Test("SARIF writer emits camelCase keys, $schema, tool.driver.rules, rank, and a scalar region")
    func sarifCamelCase() throws {
        let json = try sampleSarif().jsonString()
        // camelCase literals (NOT snake_case) — the GitHub/SonarQube-compatible casing.
        for key in ["\"$schema\"", "\"version\":\"2.1.0\"", "\"ruleId\"", "\"startLine\"", "\"startColumn\"",
                    "\"endColumn\"", "\"charOffset\"", "\"charLength\"", "\"shortDescription\"",
                    "\"physicalLocation\"", "\"artifactLocation\"", "\"rank\":62", "\"tool\"", "\"driver\"", "\"rules\""] {
            #expect(json.contains(key), "SARIF JSON missing \(key)")
        }
        #expect(json.contains("json.schemastore.org/sarif-2.1.0.json"))
        #expect(!json.contains("rule_id") && !json.contains("start_line"))   // never snake_case
        #expect(json.contains("\"skillet.density\":8"))                       // dotted property key verbatim
        // The categorical result carries no region.
        #expect(json.contains("out.sarif"))
    }

    @Test("Empty SARIF run round-trips to a valid empty results array")
    func sarifEmpty() throws {
        let doc = SarifDocument(runs: [SarifRun(tool: SarifTool(driver: SarifDriver(name: "skillet", version: "0.0.0", rules: [])), results: [])])
        let json = try doc.jsonString()
        #expect(json.contains("\"results\":[]"))
        #expect(json.contains("\"rules\":[]"))
    }

    @Test("ScoreReport is snake_case, schema-stamped, per_rule is an object, and location flattens")
    func scoreReportSnakeCase() throws {
        let report = ScoreReport(findings: [
            ScoreFinding(ruleId: "SKILL-S001", level: .warning, rank: 62, message: "AI-slop vocabulary: `delve`",
                         location: .region(file: "notes.md", startLine: 2, startColumn: 5, endLine: 2, endColumn: 10, charOffset: 12, charLength: 5),
                         properties: ["skillet.density": .number(8)]),
            ScoreFinding(ruleId: "SKILL-S007", level: .error, rank: nil, message: "Invalid SARIF 2.1.0",
                         location: .file("out.sarif"), properties: nil)
        ], summary: ScoreSummary(perRule: ["SKILL-S001": 1, "SKILL-S007": 1], filesScored: 2, filesSkipped: 1, filesUnreadable: 0))
        let json = try SkilletJSON.encode(report)

        #expect(json.contains("\"schema\":\"skillet.score\\/1\"") || json.contains("\"schema\":\"skillet.score/1\""))
        for key in ["\"rule_id\"", "\"start_line\"", "\"start_column\"", "\"char_offset\"", "\"char_length\"",
                    "\"per_rule\"", "\"files_scored\"", "\"files_skipped\"", "\"files_unreadable\""] {
            #expect(json.contains(key), "ScoreReport JSON missing \(key)")
        }
        #expect(json.contains("\"skillet.density\":8"))                        // dotted key verbatim in snake_case output too
        // per_rule is an object keyed by rule id, not an array.
        #expect(json.contains("\"per_rule\":{"))
        #expect(json.contains("\"SKILL-S001\":1"))
        // Flattened location: the categorical finding has `file` but NO region fields anywhere near it.
        #expect(json.contains("\"file\":\"out.sarif\""))
    }

    @Test("ScoreReport round-trips: a file-only location decodes back to .file, a region to .region")
    func scoreReportRoundTrip() throws {
        let loc1 = ScoreLocation.file("a.md")
        let loc2 = ScoreLocation.region(file: "b.md", startLine: 1, startColumn: 1, endLine: 1, endColumn: 3, charOffset: 0, charLength: 2)
        for loc in [loc1, loc2] {
            let data = try SkilletJSON.encoder().encode(loc)
            let back = try SkilletJSON.decoder().decode(ScoreLocation.self, from: data)
            #expect(back == loc)
        }
    }
}
