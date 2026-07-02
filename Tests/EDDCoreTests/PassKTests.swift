import Testing
import Foundation
import EDDCore

@Suite("pass^k aggregation")
struct PassKTests {
    private func verdict(_ passed: Bool) -> Verdict {
        Verdict(criterion: "c", passed: passed, rationale: "", judgeId: "j", model: "m", judgePromptVersion: "1")
    }
    /// A trial that passes (or fails) all criteria.
    private func trial(_ passed: Bool) -> TrialResult {
        TrialResult(exit: passed ? .passed : .failed, verdicts: [verdict(passed)])
    }

    @Test("Per-eval status: all-pass → PASS, zero → FAIL, partial → FLAKY (on its own recorded count)")
    func evalStatus() {
        #expect(PassK.status(passes: 3, recorded: 3) == .pass)
        #expect(PassK.status(passes: 0, recorded: 3) == .fail)
        #expect(PassK.status(passes: 2, recorded: 3) == .flaky)
        #expect(PassK.status(passes: 0, recorded: 0) == .fail)
    }

    @Test("A trial passes iff exit==passed AND every verdict passed")
    func trialPass() {
        #expect(TrialResult(exit: .passed, verdicts: [verdict(true), verdict(true)]).passed)
        #expect(!TrialResult(exit: .passed, verdicts: [verdict(true), verdict(false)]).passed)  // one criterion fails
        #expect(!TrialResult(exit: .timeout, verdicts: [verdict(true)]).passed)                 // timed out
        #expect(!TrialResult(exit: .passed, verdicts: []).passed)                               // no criteria graded → not a vacuous pass
    }

    @Test("observed_k = min recorded across evals; aggregate pass^k = fraction PASS")
    func aggregate() {
        let report = RunReport(skill: "demo", results: [
            EvalResult(evalId: "a", trials: [trial(true), trial(true), trial(true)]),   // 3/3 PASS
            EvalResult(evalId: "b", trials: [trial(true), trial(false)])                // 1/2 FLAKY
        ])
        #expect(report.observedK == 2)              // min(3, 2)
        #expect(report.passed == 1)
        #expect(report.flaky == 1)
        #expect(report.failed == 0)
        #expect(report.passK == 0.5)                // 1 of 2 evals PASS
        #expect(report.measurable)                  // observed k ≥ 2
        #expect(report.evals.first { $0.id == "a" }?.recorded == 3)   // per-row keeps its OWN count
    }

    @Test("observed k < 2 → variance unmeasurable")
    func unmeasurable() {
        let report = RunReport(skill: "demo", results: [EvalResult(evalId: "a", trials: [trial(true)])])
        #expect(report.observedK == 1)
        #expect(!report.measurable)
    }

    @Test("pass^k re-derives identically offline from per-eval (passes, recorded) — the benchmark.json path")
    func offlineRecompute() {
        let results = [
            EvalResult(evalId: "a", trials: [trial(true), trial(true)]),
            EvalResult(evalId: "b", trials: [trial(true), trial(false)])
        ]
        let live = RunReport(skill: "demo", results: results)
        // Simulate reading benchmark.json: only per-eval (passed, total) survive in the committed summary.
        let offline = RunReport(skill: "demo", counts: results.map { (id: $0.evalId, passes: $0.passes, recorded: $0.recorded) })
        #expect(live == offline)
    }

    @Test("RunReport stamps skillet.run/1 with snake_case fields")
    func schema() throws {
        let json = try SkilletJSON.encode(RunReport(skill: "demo", results: [EvalResult(evalId: "a", trials: [trial(true), trial(true)])]))
        #expect(json.contains(#""schema":"skillet.run/1""#))
        #expect(json.contains(#""observed_k":2"#))
        #expect(json.contains(#""pass_k":1"#))
        #expect(json.contains(#""pass_1":1"#))   // additive (§14-11) — exact frozen spelling
    }

    @Test("pass^1 (mean per-eval trial pass rate) complements strict pass^k — well-defined even at k=1 (§14-11)")
    func passOne() {
        let report = RunReport(skill: "demo", results: [
            EvalResult(evalId: "a", trials: [trial(true), trial(true), trial(true)]),   // rate 1.0
            EvalResult(evalId: "b", trials: [trial(true), trial(false)])                // rate 0.5
        ])
        #expect(report.passOne == 0.75)   // mean(1.0, 0.5) — τ-bench's headline metric
        #expect(report.passK == 0.5)      // the strict all-trials gate stays primary (and stricter)
        let single = RunReport(skill: "demo", results: [EvalResult(evalId: "a", trials: [trial(true)])])
        #expect(!single.measurable)       // pass^k needs observed k ≥ 2 …
        #expect(single.passOne == 1)      // … but pass^1 is meaningful at k = 1
    }
}
