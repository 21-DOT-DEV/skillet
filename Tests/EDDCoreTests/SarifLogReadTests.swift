import Testing
import Foundation
@testable import EDDCore

@Suite("SarifLog read accessors — tolerant slices for triage (F33)")
struct SarifLogReadTests {
    /// The shape `capture` actually writes (camelCase per the SARIF spec — Specs/016 assumption 6).
    let bundleSarif = """
    {
      "version": "2.1.0",
      "runs": [{
        "tool": {"driver": {"name": "skillet", "version": "0.4.0", "rules": [{"id": "SKILL-S001"}]}},
        "results": [
          {"ruleId": "SKILL-S001", "level": "warning", "rank": 55,
           "message": {"text": "over-used AI vocabulary: delve"},
           "locations": [{"physicalLocation": {"artifactLocation": {"uri": "notes.md"}}}]},
          {"ruleId": "SKILL-S004", "level": "error", "message": {"text": "rule-of-three over-use"}}
        ]
      }]
    }
    """

    @Test func slicesTheCaptureShape() throws {
        let log = try JSONDecoder().decode(SarifLog.self, from: Data(bundleSarif.utf8))
        #expect(log.toolVersion == "0.4.0")
        let slices = log.resultSlices
        #expect(slices.count == 2)
        #expect(slices[0] == SarifResultSlice(ruleId: "SKILL-S001", level: "warning",
                                              message: "over-used AI vocabulary: delve"))
        #expect(slices[1].ruleId == "SKILL-S004")
        #expect(slices[1].level == "error")
    }

    @Test func toleratesForeignAndMissingFields() throws {
        // A foreign tool: no driver version, a bare-string message (nonstandard), a result with no
        // level, an unknown future level — every gap slices to nil / passes through, never a throw.
        let foreign = """
        {"version": "2.1.0", "runs": [{
          "tool": {"driver": {"name": "other"}},
          "results": [
            {"ruleId": "X-1", "message": "bare string message"},
            {"ruleId": "X-2", "level": "catastrophic", "message": {"text": "m"}},
            {"level": "note"}
          ],
          "somethingUnknown": {"kept": true}
        }]}
        """
        let log = try JSONDecoder().decode(SarifLog.self, from: Data(foreign.utf8))
        #expect(log.toolVersion == nil)
        let slices = log.resultSlices
        #expect(slices[0].message == "bare string message")     // bare-string tolerance
        #expect(slices[0].level == nil)
        #expect(slices[1].level == "catastrophic")              // unknown level survives as raw string
        #expect(slices[2].ruleId == nil)                        // missing ruleId → nil, consumer discloses
    }

    @Test func emptyAndRunlessLogsYieldNothing() throws {
        let empty = try JSONDecoder().decode(SarifLog.self, from: Data(#"{"version": "2.1.0"}"#.utf8))
        #expect(empty.toolVersion == nil)
        #expect(empty.resultSlices.isEmpty)
    }
}
