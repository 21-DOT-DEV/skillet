import Testing
import Foundation
import EDDCore

@Suite("Committed judge_id provenance (F16)")
struct GroundedProvenanceTests {
    private func trial(_ passed: Bool) -> TrialResult {
        TrialResult(exit: .passed, verdicts: [Verdict(criterion: "c", passed: passed, rationale: "r", judgeId: "grounded-judge", model: "m", judgePromptVersion: "v1")])
    }
    private let grounded = RunProvenance(
        judgeId: "grounded-judge", judgeProvider: "claude-code", judgeModel: "m",
        judgePromptVersion: "v1", executorBinaryVersion: "2.1.0"
    )

    @Test("benchmark.json metadata.judge carries the additive id (so grounded vs text survive a cache wipe)")
    func benchmarkJudgeId() {
        let evals = [EvalResult(evalId: "a", trials: [trial(true)])]
        let bench = BenchmarkFile(report: RunReport(skill: "demo", results: evals), evals: evals, harness: "claude-code", k: 1, provenance: grounded)
        #expect(bench.metadata?["judge"]?.objectValue?["id"]?.stringValue == "grounded-judge")
        #expect(bench.metadata?["judge"]?.objectValue?["prompt_version"]?.stringValue == "v1")   // now versions *within* the grounded lineage
    }

    @Test("grading.json judge block carries the additive id")
    func gradingJudgeId() {
        let grading = GradingFile(evals: [EvalResult(evalId: "a", trials: [trial(true)])], provenance: grounded)
        #expect(grading.fields["judge"]?.objectValue?["id"]?.stringValue == "grounded-judge")
    }

    @Test("A judge-free trigger-only run carries the prior committed judge block (incl. its id) verbatim")
    func triggerOnlyCarriesJudgeId() {
        let evals = [EvalResult(evalId: "a", trials: [trial(true)])]
        let prior = BenchmarkFile(report: RunReport(skill: "demo", results: evals), evals: evals, harness: "claude-code", k: 1, provenance: grounded)
        let trigger = [TriggerEvalResult(evalId: "t0", query: "q", shouldTrigger: true, trials: [TriggerTrialResult(exit: .passed, firedTarget: true)])]
        // A trigger-only run builds no judge — the sentinel "none" must not overwrite the carried block.
        let none = RunProvenance(judgeId: "none", judgeProvider: "none", judgeModel: "none", judgePromptVersion: "none", executorBinaryVersion: "2.1.0")
        let merged = BenchmarkFile(skill: "demo", behavioral: nil, trigger: trigger, harness: "claude-code", k: 1, provenance: none, preserving: prior)
        #expect(merged.metadata?["judge"]?.objectValue?["id"]?.stringValue == "grounded-judge")
    }

    @Test("Default provenance id is text-judge (existing single-arm/text runs stay labelled correctly)")
    func defaultIsTextJudge() {
        let p = RunProvenance(judgeProvider: "claude-code", judgeModel: "m", judgePromptVersion: "v2", executorBinaryVersion: "x")
        #expect(p.judgeId == "text-judge")
        let bench = BenchmarkFile(report: RunReport(skill: "demo", results: [EvalResult(evalId: "a", trials: [trial(true)])]),
                                  evals: [EvalResult(evalId: "a", trials: [trial(true)])], harness: "claude-code", k: 1, provenance: p)
        #expect(bench.metadata?["judge"]?.objectValue?["id"]?.stringValue == "text-judge")
    }
}
