import Testing
import EDDCore
@testable import AnalysisKit

@Suite("TriageEngine — pure clustering/routing/join core (F33)")
struct TriageEngineTests {
    let runDate = "2026-07-19"
    let version = "0.4.0"

    func hit(_ ruleId: String, level: String = "warning", message: String = "m") -> SarifResultSlice {
        SarifResultSlice(ruleId: ruleId, level: level, message: message)
    }
    func bundle(_ stem: String, tool: String? = "0.4.0", skillVersion: String? = "1.0.0",
                model: String? = "m1", results: [SarifResultSlice]) -> BundleInput {
        BundleInput(stem: stem, skillVersion: skillVersion, model: model, toolVersion: tool, results: results)
    }
    func run(_ bundles: [BundleInput], existing: [ExistingFindingRef] = [],
             friction: [FrictionRef] = [], disclosures: [DisclosedInput] = []) -> SkillTriageResult {
        TriageEngine.triage(skill: "s", runDate: runDate, runningVersion: version,
                            bundles: bundles, disclosures: disclosures,
                            existingFindings: existing, friction: friction)
    }

    @Test func clustersByRuleRankedByHitsThenSlug() {
        let result = run([
            bundle("2026-06-01-a", results: [hit("SKILL-S002"), hit("SKILL-S001"), hit("SKILL-S001")]),
            bundle("2026-06-02-b", results: [hit("SKILL-S001"), hit("SKILL-S002")]),
        ])
        #expect(result.clusters.map(\.cluster) == ["slop-vocabulary", "puffery"])   // 3 hits, then 2
        #expect(result.clusters[0].hits == 3)
        #expect(result.clusters[0].recordings == ["2026-06-01-a", "2026-06-02-b"])
        #expect(result.clusters[0].totalRecordings == 2)
        // Equal hits → slug ascending (stable tie-break).
        let tied = run([bundle("2026-06-01-a", results: [hit("SKILL-S003"), hit("SKILL-S002")])])
        #expect(tied.clusters.map(\.cluster) == ["em-dash", "puffery"])
    }

    @Test func deterministicRegardlessOfInputOrder() {
        let a = bundle("2026-06-01-a", results: [hit("SKILL-S001")])
        let b = bundle("2026-06-02-b", results: [hit("SKILL-S001"), hit("SKILL-S004")])
        #expect(run([a, b]) == run([b, a]))   // byte-identical result either way
    }

    @Test func coverageAndUnknownRulesAreDisclosedNotClustered() {
        let result = run([bundle("2026-06-01-a", results: [
            hit("SKILL-S000", level: "note"), hit("SKILL-S000", level: "note"),
            hit("SKILL-S999"), SarifResultSlice(ruleId: nil, level: nil, message: nil),
        ])])
        #expect(result.clusters.isEmpty)
        #expect(result.unreadableHits == 2)                       // S000 → coverage note
        #expect(result.disclosures.contains { $0.subject == "SKILL-S999" && $0.reason.contains("unknown rule id") })
        #expect(result.disclosures.contains { $0.subject == "2026-06-01-a" && $0.reason.contains("without a ruleId") })
    }

    @Test func worstLevelRanksErrorAboveWarningToleratingUnknowns() {
        let result = run([bundle("2026-06-01-a", results: [
            hit("SKILL-S001", level: "warning"), hit("SKILL-S001", level: "error"),
            hit("SKILL-S001", level: "catastrophic"),   // unknown level: survives, ranks lowest
        ])])
        #expect(result.clusters[0].worstLevel == "error")
    }

    @Test func allUnknownLevelsSurviveVerbatimNeverEmpty() {
        // Round 1: `-1 > -1` never set `worst`, so an all-unknown cluster reported "" everywhere.
        let result = run([bundle("2026-06-01-a", results: [
            hit("SKILL-S001", level: "catastrophic"), hit("SKILL-S001", level: "catastrophic"),
        ])])
        #expect(result.clusters[0].worstLevel == "catastrophic")
        #expect(try! #require(result.newFindings.first).finding.signal
            == "hits=2 recordings=1/1 worst=catastrophic")   // the signal carries it too, never ""
    }

    @Test func absentLevelDefaultsToWarningPerSarifSpec() {
        // SARIF 2.1.0 §3.27.10: a result with no `level` (and no rule defaultLevel in the slice)
        // means "warning" — the spec's terminal default, not a fabricated "unknown".
        let result = run([bundle("2026-06-01-a", results: [
            SarifResultSlice(ruleId: "SKILL-S001", level: nil, message: "m"),
        ])])
        #expect(result.clusters[0].worstLevel == "warning")
    }

    @Test func unknownFirstThenKnownRanksTheKnown() {
        // First-hit-sets must not freeze an unranked level over a later ranked one.
        let result = run([bundle("2026-06-01-a", results: [
            hit("SKILL-S001", level: "weird"), hit("SKILL-S001", level: "note"),
        ])])
        #expect(result.clusters[0].worstLevel == "note")   // rank 1 beats unranked
    }

    @Test func stalenessCountsDifferentAndMissingToolVersions() {
        let result = run([
            bundle("2026-06-01-a", tool: "0.4.0", results: [hit("SKILL-S001")]),
            bundle("2026-06-02-b", tool: "0.3.0", results: []),
            bundle("2026-06-03-c", tool: nil, results: []),
        ])
        #expect(result.staleRecordings == 2)
        #expect(result.totalRecordings == 3)
    }

    @Test func joinsFrictionOnSharedSessions() {
        let result = run(
            [bundle("2026-06-01-a", results: [hit("SKILL-S001")]),
             bundle("2026-06-02-b", results: [hit("SKILL-S004")])],
            friction: [
                FrictionRef(id: "2026-06-07-f1", sessions: ["2026-06-01-a", "unrelated"]),
                FrictionRef(id: "2026-06-08-f2", sessions: ["nope"]),
                FrictionRef(id: "2026-06-09-f3", sessions: ["2026-06-01-a"]),
            ])
        let slop = result.clusters.first { $0.cluster == "slop-vocabulary" }
        #expect(slop?.linkedFriction == ["2026-06-07-f1", "2026-06-09-f3"])   // sorted, disjoint excluded
        let rule3 = result.clusters.first { $0.cluster == "rule-of-three" }
        #expect(rule3?.linkedFriction == [])
    }

    @Test func existingClusterIsNeverResynthesized() {
        let result = run(
            [bundle("2026-06-01-a", results: [hit("SKILL-S001")])],
            existing: [ExistingFindingRef(id: "2026-07-01-slop-vocabulary", cluster: "slop-vocabulary", state: .candidate)])
        #expect(result.clusters[0].fileStatus == "exists")
        #expect(result.clusters[0].findingId == "2026-07-01-slop-vocabulary")   // the on-file id, not a new one
        #expect(result.clusters[0].state == .candidate)
        #expect(result.newFindings.isEmpty)                                     // nothing to write (D3)
    }

    @Test func closedStillFiringIsReportedNeverReopened() {
        let result = run(
            [bundle("2026-06-01-a", results: [hit("SKILL-S002")])],
            existing: [ExistingFindingRef(id: "2026-07-01-puffery", cluster: "puffery", state: .closed)])
        #expect(result.clusters[0].fileStatus == "closed-still-firing")
        #expect(result.newFindings.isEmpty)   // no auto-reopen, no duplicate (GitHub-dismissal model)
    }

    @Test func synthesizesTheFindingPerA6() {
        let result = run([
            bundle("2026-06-02-b", skillVersion: "1.2.0", model: "opus",
                   results: [hit("SKILL-S004", level: "error", message: "rule-of-three over-use")]),
            bundle("2026-06-01-a", skillVersion: "1.2.0", model: "opus",
                   results: [hit("SKILL-S004", level: "warning")]),
            bundle("2026-06-03-c", results: []),   // non-contributing: not in sessions
        ])
        let new = try! #require(result.newFindings.first)
        let f = new.finding
        #expect(f.header.id == "2026-07-19-rule-of-three")
        #expect(f.header.domain == "s")                       // skill-name sentinel (H)
        #expect(f.header.state == .logged)
        #expect(f.header.lever == .skillMd)
        #expect(f.header.sessions == ["2026-06-01-a", "2026-06-02-b"])   // sorted contributing stems
        #expect(f.header.skillVersion == "1.2.0")             // unanimous across contributing
        #expect(f.header.model == "opus")
        #expect(f.cluster == "rule-of-three")
        #expect(f.signal == "hits=2 recordings=2/3 worst=error")
        #expect(new.body.contains("2 hit(s) of SKILL-S004"))
        #expect(new.body.contains("- 2026-06-01-a: 1 hit(s)"))
        #expect(new.body.contains("hypothesis, not a verdict"))
    }

    @Test func mixedProvenanceFallsBackToUnknown() {
        let result = run([
            bundle("2026-06-01-a", skillVersion: "1.0.0", model: "m1", results: [hit("SKILL-S001")]),
            bundle("2026-06-02-b", skillVersion: "1.1.0", model: nil, results: [hit("SKILL-S001")]),
        ])
        let f = try! #require(result.newFindings.first).finding
        #expect(f.header.skillVersion == "unknown")   // disagreement → sentinel
        #expect(f.header.model == "unknown")          // a nil vote → sentinel
    }

    @Test func emptyCorpusYieldsEmptyResult() {
        let result = run([])
        #expect(result.clusters.isEmpty && result.newFindings.isEmpty && result.totalRecordings == 0)
    }
}
