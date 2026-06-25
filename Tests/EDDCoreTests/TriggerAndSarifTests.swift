import Testing
import Foundation
import EDDCore

@Suite("trigger-eval + SARIF codecs")
struct TriggerAndSarifTests {
    @Test("trigger-eval.json: counts + faithful round-trip (unknown key preserved)")
    func triggerEval() throws {
        let json = """
        [{"query":"a","should_trigger":true},{"query":"b","should_trigger":true},{"query":"c","should_trigger":true},
         {"query":"d","should_trigger":false},{"query":"e","should_trigger":false,"note":"near-miss"}]
        """
        let f = try JSONDecoder().decode(TriggerEvalFile.self, from: Data(json.utf8))
        #expect(f.caseCount == 5)
        #expect(f.shouldTriggerCount == 3)
        #expect(f.shouldNotTriggerCount == 2)
        #expect(f.cases[4].query == "e")
        let out = try JSONEncoder().encode(f)
        #expect(try jsonSemanticEqual(Data(json.utf8), out))  // "note" preserved
    }

    @Test("SARIF 2.1.0 subset: accessors; unknown level + properties bag preserved; round-trip")
    func sarif() throws {
        let json = """
        {"$schema":"https://json.schemastore.org/sarif-2.1.0.json","version":"2.1.0",
         "runs":[{"tool":{"driver":{"name":"skillet","rules":[]}},
           "results":[{"ruleId":"SKILL-S001","level":"future-level","message":{"text":"x"},
             "locations":[],"properties":{"skillet":"extra"}}]}]}
        """
        let s = try JSONDecoder().decode(SarifLog.self, from: Data(json.utf8))
        #expect(s.version == "2.1.0")
        #expect(s.schemaURI?.contains("sarif-2.1.0") == true)
        #expect(s.runs.count == 1)
        let result0 = s.runs[0].objectValue?["results"]?.arrayValue?[0].objectValue
        #expect(result0?["level"] == .string("future-level"))                     // unrecognized enum preserved
        #expect(result0?["properties"]?.objectValue?["skillet"] == .string("extra"))
        let out = try JSONEncoder().encode(s)
        #expect(try jsonSemanticEqual(Data(json.utf8), out))
    }

    @Test("SARIF audit role derives from filename")
    func sarifRole() {
        #expect(SarifRole(filename: "2026-05-19-baseline.audit-baseline.sarif") == .auditBaseline)
        #expect(SarifRole(filename: "2026-05-19-baseline.audit-input.sarif") == .auditInput)
        #expect(SarifRole(filename: "2026-05-19.trace.json") == nil)
    }
}
