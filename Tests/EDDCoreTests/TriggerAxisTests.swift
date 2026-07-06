import Testing
import Foundation
import EDDCore

@Suite("Trigger axis — models, report block, benchmark mapping (F14)")
struct TriggerAxisTests {
    private func result(_ id: String, should: Bool, fires: [Bool], exits: [TrialExit]? = nil) -> TriggerEvalResult {
        TriggerEvalResult(evalId: id, query: "q-\(id)", shouldTrigger: should, trials: fires.enumerated().map {
            TriggerTrialResult(exit: exits?[$0.offset] ?? .passed, firedTarget: $0.element)
        })
    }

    @Test("A trial passes iff it ran cleanly and firing matched should_trigger")
    func passSemantics() {
        #expect(result("t", should: true, fires: [true, true]).passes == 2)
        #expect(result("t", should: true, fires: [true, false]).passes == 1)      // flaky trigger
        #expect(result("t", should: false, fires: [false, false]).passes == 2)    // correct non-fire
        #expect(result("t", should: false, fires: [true]).passes == 0)            // near-miss misfire
        #expect(result("t", should: true, fires: [true], exits: [.timeout]).passes == 0)  // unmeasured ≠ pass
    }

    @Test("RunReport gains an additive trigger block; behavioral fields keep their meaning")
    func reportTriggerBlock() throws {
        let behavioral = [EvalResult(evalId: "b1", trials: [])]
        let trigger = [result("trigger-0", should: true, fires: [true, true]),
                       result("trigger-1", should: false, fires: [true, false])]
        let report = RunReport(skill: "demo", results: behavioral, trigger: trigger)
        #expect(report.evals.count == 1)
        #expect(report.trigger?.evals.count == 2)
        #expect(report.trigger?.passed == 1)
        #expect(report.trigger?.flaky == 1)
        let encoded = try SkilletJSON.encode(report)
        #expect(encoded.contains(#""trigger":{"#))
        #expect(encoded.contains(#""pass_1""#))
        // Absent axis ⇒ absent key (additive contract).
        let plain = try SkilletJSON.encode(RunReport(skill: "demo", results: behavioral))
        #expect(!plain.contains(#""trigger""#))
    }

    @Test("Benchmark: trigger rows ride configuration \"trigger\" with axis-marked per_eval entries")
    func benchmarkTriggerMapping() throws {
        let trigger = [result("trigger-0", should: false, fires: [false])]
        let file = BenchmarkFile(
            skill: "demo",
            behavioral: nil, trigger: trigger, harness: "replay", k: 1,
            provenance: RunProvenance(judgeProvider: "none", judgeModel: "none", judgePromptVersion: "none", executorBinaryVersion: "replay-1"),
            preserving: nil
        )
        let rows = file.runs.compactMap(\.objectValue)
        #expect(rows.count == 1)
        #expect(rows[0]["configuration"]?.stringValue == "trigger")
        #expect(rows[0]["expectations"]?.arrayValue?.first?.objectValue?["text"]?.stringValue == "skill does not trigger")
        #expect(file.skillName == "demo")   // never "unknown" on a trigger-only first run
        #expect(file.triggerCounts.map(\.id) == ["trigger-0"])
        #expect(file.evalCounts.isEmpty)   // the behavioral recompute never mixes axes
    }

    @Test("Round-trip: both axes re-derive offline from one committed benchmark.json (P2/D3)")
    func recomputeBothAxes() throws {
        let behavioral = [EvalResult(evalId: "b1", trials: [TrialResult(exit: .passed, verdicts: [
            Verdict(criterion: "c", passed: true, rationale: "r", judgeId: "j", model: "m", judgePromptVersion: "v2")
        ])])]
        let report = RunReport(skill: "demo", results: behavioral)
        let trigger = [result("trigger-0", should: true, fires: [true, true])]
        let file = BenchmarkFile(
            skill: "demo",
            behavioral: (report: report, evals: behavioral), trigger: trigger, harness: "replay", k: 2,
            provenance: RunProvenance(judgeProvider: "p", judgeModel: "m", judgePromptVersion: "v", executorBinaryVersion: "e"),
            preserving: nil
        )
        let data = try JSONEncoder().encode(file)
        let reread = try JSONDecoder().decode(BenchmarkFile.self, from: data)
        let recomputed = RunReport(benchmark: reread)
        #expect(recomputed.evals.map(\.id) == ["b1"])
        #expect(recomputed.trigger?.evals.map(\.id) == ["trigger-0"])
        #expect(recomputed.trigger?.passed == 1)
        #expect(recomputed.skill == "demo")
    }

    @Test("Axis merge: a trigger-only run preserves the prior behavioral record, and vice versa")
    func axisMergePreserves() throws {
        let behavioral = [EvalResult(evalId: "b1", trials: [TrialResult(exit: .passed, verdicts: [
            Verdict(criterion: "c", passed: true, rationale: "r", judgeId: "j", model: "m", judgePromptVersion: "v2")
        ])])]
        let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m", judgePromptVersion: "v", executorBinaryVersion: "e")
        let first = BenchmarkFile(
            skill: "demo",
            behavioral: (report: RunReport(skill: "demo", results: behavioral), evals: behavioral),
            trigger: nil, harness: "replay", k: 3, provenance: provenance, preserving: nil
        )
        // Trigger-only second run (different k + harness), preserving the behavioral axis.
        let second = BenchmarkFile(
            skill: "demo",
            behavioral: nil, trigger: [result("trigger-0", should: true, fires: [true])],
            harness: "replay2", k: 1,
            provenance: RunProvenance(judgeProvider: "none", judgeModel: "none", judgePromptVersion: "none", executorBinaryVersion: "e2"),
            preserving: first
        )
        #expect(second.evalCounts.map(\.id) == ["b1"])            // behavioral carried
        #expect(second.triggerCounts.map(\.id) == ["trigger-0"])  // trigger fresh
        #expect(second.metadata?["judge"]?.objectValue?["model"]?.stringValue == "m")   // judge provenance carried
        // Behavioral-owned metadata follows the same carry rule (round 2, finding 3): a k=1
        // trigger-only run must not relabel a k=3 behavioral record at the top level.
        #expect(second.metadata?["k"]?.numberValue == 3)
        #expect(second.metadata?["runs_per_configuration"]?.numberValue == 3)
        #expect(second.metadata?["harness"]?.stringValue == "replay")
        // Behavioral-only third run, preserving the trigger axis.
        let third = BenchmarkFile(
            skill: "demo",
            behavioral: (report: RunReport(skill: "demo", results: behavioral), evals: behavioral),
            trigger: nil, harness: "replay", k: 1, provenance: provenance, preserving: second
        )
        #expect(third.triggerCounts.map(\.id) == ["trigger-0"])   // trigger carried
        #expect(third.evalCounts.map(\.id) == ["b1"])
    }
}
