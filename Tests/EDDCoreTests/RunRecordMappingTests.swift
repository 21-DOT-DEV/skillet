import Testing
import Foundation
import EDDCore

@Suite("Run-record mapping (benchmark.json / grading.json)")
struct RunRecordMappingTests {
    private func verdict(_ criterion: String, _ passed: Bool) -> Verdict {
        Verdict(criterion: criterion, passed: passed, rationale: passed ? "ok" : "missing \(criterion)",
                judgeId: "text-judge", model: "m", judgePromptVersion: "v1")
    }
    private func trial(_ passed: Bool, _ criteria: [String] = ["c"]) -> TrialResult {
        TrialResult(exit: .passed, verdicts: criteria.map { verdict($0, passed) })
    }
    private let judge = SkilletConfig.Judge()

    @Test("benchmark.json: per-trial viewer-shaped runs[], skillet-owned consistency, run_summary.default")
    func benchmarkShape() {
        let evals = [
            EvalResult(evalId: "a", trials: [trial(true, ["x", "y"]), trial(true, ["x", "y"])]),   // 2 trials × 2 expectations, all pass → PASS
            EvalResult(evalId: "b", trials: [trial(true, ["z"]), trial(false, ["z"])])             // 1/2 trials → FLAKY
        ]
        let bench = BenchmarkFile(report: RunReport(skill: "demo", results: evals), evals: evals, harness: "replay", k: 2, judge: judge)
        #expect(bench.skillName == "demo")
        #expect(bench.runs.count == 4)   // ONE ROW PER TRIAL (2 evals × 2 trials), not per eval

        let first = bench.runs.first?.objectValue
        #expect(first?["configuration"] == .string("default"))   // string arm label, not an object
        #expect(first?["eval_id"] == .string("a"))
        #expect(first?["run_number"] == .number(1))
        #expect(first?["expectations"]?.arrayValue?.count == 2)
        #expect(first?["result"]?.objectValue?["total"] == .number(2))    // EXPECTATIONS in that trial

        let consistency = bench.fields["consistency"]?.objectValue
        #expect(consistency?["k"] == .number(2))
        #expect(consistency?["suite_pass_power_k"] == .number(0.5))       // 1 of 2 evals pass^k
        #expect(consistency?["flaky_eval_ids"]?.arrayValue == [.string("b")])
        let perEvalA = consistency?["per_eval"]?.arrayValue?.first?.objectValue
        #expect(perEvalA?["eval_id"] == .string("a"))
        #expect(perEvalA?["perfect_passes"] == .number(2))
        #expect(perEvalA?["runs"] == .number(2))
        #expect(perEvalA?["pass_power_k"] == .number(1))

        #expect(bench.runSummary?["default"]?.objectValue?["pass_rate"]?.objectValue?["max"] == .number(1))
        #expect(bench.metadata?["judge"]?.objectValue?["provider"]?.stringValue == "claude-code")
    }

    @Test("runs[].result counts EXPECTATIONS in that trial, not trials — no viewer-semantics overload")
    func resultIsExpectationCounts() {
        // One eval, one trial, 3 expectations, 2 pass → result is 2/3, NOT the trial-level 0/1 or 1/1.
        let evals = [EvalResult(evalId: "a", trials: [TrialResult(exit: .passed, verdicts: [verdict("x", true), verdict("y", true), verdict("z", false)])])]
        let result = BenchmarkFile(report: RunReport(skill: "demo", results: evals), evals: evals, harness: "replay", k: 1, judge: judge)
            .runs.first?.objectValue?["result"]?.objectValue
        #expect(result?["passed"] == .number(2))
        #expect(result?["failed"] == .number(1))
        #expect(result?["total"] == .number(3))
        #expect(result?["pass_rate"] == .number(2.0 / 3.0))
    }

    @Test("pass^k re-derives from the committed benchmark.json via consistency across a round-trip (P2/D3)")
    func reDeriveFromCommittedRecord() throws {
        let evals = [
            EvalResult(evalId: "a", trials: [trial(true), trial(true)]),
            EvalResult(evalId: "b", trials: [trial(true), trial(false)]),
            EvalResult(evalId: "c", trials: [trial(false), trial(false)])
        ]
        let live = RunReport(skill: "demo", results: evals)
        // Producer side: serialize the committed record.
        let json = String(decoding: try JSONEncoder().encode(BenchmarkFile(report: live, evals: evals, harness: "replay", k: 2, judge: judge)), as: UTF8.self)
        // Consumer side: read it back and recompute pass^k offline from consistency — no in-memory results, no cache.
        let reloaded = try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
        #expect(RunReport(benchmark: reloaded) == live)
    }

    @Test("Offline recompute coerces a numeric eval_id (real records use numbers) — the row is not dropped")
    func reDeriveCoercesNumericEvalId() throws {
        // A real-shaped record whose consistency.per_eval uses a NUMERIC eval_id (skill-creator convention).
        let json = """
        {"metadata":{"skill_name":"demo"},
         "consistency":{"k":2,"meaningful":true,"suite_pass_power_k":1,"flaky_eval_ids":[],
           "per_eval":[{"eval_id":0,"runs":2,"perfect_passes":2,"pass_power_k":1,"flaky":false,"mean_pass_rate":1}]}}
        """
        let report = RunReport(benchmark: try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8)))
        #expect(report.evals.count == 1)            // not silently dropped despite the numeric id
        #expect(report.evals.first?.id == "0")      // coerced number → string
        #expect(report.evals.first?.status == .pass)
    }

    @Test("grading.json: a criterion passes iff it held in EVERY trial; summary counts match")
    func gradingShape() {
        let evals = [
            EvalResult(evalId: "a", trials: [trial(true, ["x"]), trial(true, ["x"])]),    // x: 2/2 → passed
            EvalResult(evalId: "b", trials: [trial(true, ["y"]), trial(false, ["y"])])    // y: 1/2 → not consistent
        ]
        let grading = GradingFile(evals: evals)
        #expect(grading.expectations.count == 2)
        let x = grading.expectations.first { $0.objectValue?["text"]?.stringValue == "x" }
        let y = grading.expectations.first { $0.objectValue?["text"]?.stringValue == "y" }
        #expect(x?.objectValue?["passed"]?.boolValue == true)
        #expect(y?.objectValue?["passed"]?.boolValue == false)
        #expect(y?.objectValue?["evidence"]?.stringValue == "missing y")   // the failing trial's rationale
        #expect(grading.passed == 1)
        #expect(grading.total == 2)
        #expect(grading.passRate == 0.5)
    }

    @Test("A trial with no verdicts (errored) contributes no grading rows")
    func gradingSkipsErroredEvals() {
        let evals = [EvalResult(evalId: "e", trials: [TrialResult(exit: .timeout, verdicts: [])])]
        let grading = GradingFile(evals: evals)
        #expect(grading.expectations.isEmpty)
        #expect(grading.total == 0)
    }

    @Test("A criterion judged in only some trials (another timed out) does NOT count as passed")
    func gradingRequiresEveryTrialJudged() {
        let evals = [EvalResult(evalId: "a", trials: [
            trial(true, ["x"]),                          // judged + passed
            TrialResult(exit: .timeout, verdicts: [])    // no verdicts for "x"
        ])]
        let grading = GradingFile(evals: evals)
        let x = grading.expectations.first { $0.objectValue?["text"]?.stringValue == "x" }
        #expect(x?.objectValue?["passed"]?.boolValue == false)   // not judged in every trial
        #expect(x?.objectValue?["evidence"]?.stringValue?.contains("not graded") == true)
        #expect(grading.passed == 0)
        #expect(grading.total == 1)
    }
}
