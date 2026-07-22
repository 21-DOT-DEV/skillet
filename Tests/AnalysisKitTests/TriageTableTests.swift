import Testing
import EDDCore
@testable import AnalysisKit

@Suite("TriageTable — the fixed routing + confidence catalog (D4/D5)")
struct TriageTableTests {
    @Test func oneRowPerActiveScorerRuleAllUnique() {
        #expect(TriageTable.rules.count == 7)                    // S001–S007; S000 is coverage, not a row
        #expect(Set(TriageTable.rules.map(\.ruleId)).count == 7)
        #expect(Set(TriageTable.rules.map(\.slug)).count == 7)   // slugs are the stable cluster keys
        #expect(TriageTable.rule(for: TriageTable.coverageRuleId) == nil)
    }

    @Test func experimentalRuleStampsMediumEverythingElseHigh() {
        for rule in TriageTable.rules {
            #expect(rule.confidence == (rule.ruleId == "SKILL-S006" ? .medium : .high))
        }
    }

    @Test func routingHypothesesMatchThePlanTable() {
        #expect(TriageTable.rule(for: "SKILL-S001")?.slug == "slop-vocabulary")
        #expect(TriageTable.rule(for: "SKILL-S001")?.lever == .skillMd)
        #expect(TriageTable.rule(for: "SKILL-S007")?.lever == .eval)   // output validity → validity eval
        #expect(TriageTable.rule(for: "SKILL-S999") == nil)            // unknown ids stay unknown
    }
}
