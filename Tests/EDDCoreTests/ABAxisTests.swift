import Testing
import Foundation
import EDDCore

@Suite("A/B baseline (F15) — paired math, report block, benchmark mapping")
struct ABAxisTests {
    private func verdict(_ criterion: String, _ passed: Bool) -> Verdict {
        Verdict(criterion: criterion, passed: passed, rationale: "r", judgeId: "j", model: "m", judgePromptVersion: "v")
    }
    private func trial(_ passed: Bool, criteria: [String] = ["c"], exit: TrialExit = .passed, seconds: Double? = nil) -> TrialResult {
        TrialResult(exit: exit, verdicts: exit == .polluted ? [] : criteria.map { verdict($0, passed) }, durationSeconds: seconds)
    }
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m", judgePromptVersion: "v", executorBinaryVersion: "x")

    // MARK: - paired-difference math

    @Test("pairedStats is honest at the edges: empty (0, nil), single (d, nil), Bessel SE at n ≥ 2")
    func pairedStats() {
        let empty = ABComparison.pairedStats([])
        #expect(empty.mean == 0)
        #expect(empty.se == nil)
        let single = ABComparison.pairedStats([0.5])
        #expect(single.mean == 0.5)
        #expect(single.se == nil)   // too few to state uncertainty — never invented
        let pair = ABComparison.pairedStats([1.0, 0.0])
        #expect(pair.mean == 0.5)
        #expect(abs((pair.se ?? 0) - 0.5) < 1e-9)   // sample sd √0.5 / √2 = 0.5
        let flat = ABComparison.pairedStats([0.25, 0.25, 0.25])
        #expect(flat.mean == 0.25)
        #expect(flat.se == 0)
    }

    @Test("ABComparison: flips, paired deltas, flaky-untrusted, pollution exclusion, time Δ")
    func liveComparison() {
        let withArm = [
            EvalResult(evalId: "flip-up", trials: [trial(true, seconds: 3), trial(true, seconds: 3)]),      // PASS 2/2
            EvalResult(evalId: "flip-down", trials: [trial(false, seconds: 3), trial(false, seconds: 3)]),  // FAIL 0/2
            EvalResult(evalId: "shaky", trials: [trial(true, seconds: 3), trial(false, seconds: 3)])        // FLAKY 1/2
        ]
        let baseline = [
            EvalResult(evalId: "flip-up", trials: [trial(false, seconds: 1), trial(false, seconds: 1)]),    // FAIL 0/2
            EvalResult(evalId: "flip-down", trials: [trial(true, seconds: 1), trial(true, seconds: 1)]),    // PASS 2/2
            EvalResult(evalId: "shaky", trials: [trial(false, seconds: 1), trial(false, exit: .polluted)])  // 0/1 measured + 1 polluted
        ]
        let ab = ABComparison(withArm: withArm, baseline: baseline)
        #expect(ab.flipsUp == 1)
        #expect(ab.flipsDown == 1)
        #expect(ab.polluted == 1)
        #expect(ab.untrustedEvalIds == ["shaky"])
        #expect(ab.perEval[0].delta == 1.0)
        #expect(ab.perEval[1].delta == -1.0)
        #expect(ab.perEval[2].delta == 0.5)       // with 1/2 − baseline 0/1 measured
        #expect(abs(ab.pairedMeanDelta - 0.5 / 3) < 1e-9)
        #expect(ab.pairedSE != nil)
        #expect(abs((ab.timeDeltaSeconds ?? 0) - 2.0) < 1e-9)   // 3s mean − 1s mean (polluted duration excluded)
        #expect(ab.baseline.evals[2].recorded == 1)             // polluted excluded from the arm's counts
        #expect(ab.unmeasuredEvalIds.isEmpty)                   // every pair here has measured trials
    }

    @Test("A baseline eval that never ran is an UNMEASURED pair — no Δ, no flip, never a fabricated +1.00")
    func missingBaselinePairIsUnmeasured() {
        let ab = ABComparison(withArm: [EvalResult(evalId: "only-with", trials: [trial(true)])], baseline: [])
        #expect(ab.perEval[0].baselineRecorded == 0)
        #expect(ab.perEval[0].delta == nil)
        #expect(ab.unmeasuredEvalIds == ["only-with"])
        #expect(ab.flipsUp == 0)
        #expect(ab.pairedMeanDelta == 0)   // no measured deltas — nothing to average
        #expect(ab.pairedSE == nil)
    }

    @Test("An entirely polluted baseline manufactures NO skill effect (review finding, 2026-07-07)")
    func allPollutedBaselineNoFakeEffect() {
        let withArm = [EvalResult(evalId: "e", trials: [trial(true)])]
        let baseline = [EvalResult(evalId: "e", trials: [trial(false, exit: .polluted), trial(false, exit: .polluted)])]
        let ab = ABComparison(withArm: withArm, baseline: baseline)
        #expect(ab.polluted == 2)
        #expect(ab.unmeasuredEvalIds == ["e"])
        #expect(ab.perEval[0].delta == nil)
        #expect(ab.flipsUp == 0)           // the old behavior reported +1.00 / 1↑ off zero evidence
        #expect(ab.pairedMeanDelta == 0)
        #expect(ab.pairedSE == nil)
    }

    // MARK: - skillet.run/1

    @Test("skillet.run/1 gains the additive ab block; single-arm reports omit the key; pass_1 spelling untouched")
    func reportJSON() throws {
        let withArm = [EvalResult(evalId: "e", trials: [trial(true)])]
        let baseline = [EvalResult(evalId: "e", trials: [trial(false)])]
        let ab = try SkilletJSON.encode(RunReport(skill: "demo", results: withArm, baseline: baseline))
        #expect(ab.contains(#""ab":"#))
        #expect(ab.contains(#""paired_mean_delta""#))
        #expect(ab.contains(#""flips_up""#))
        #expect(ab.contains(#""pass_1""#))
        let single = try SkilletJSON.encode(RunReport(skill: "demo", results: withArm))
        #expect(!single.contains(#""ab":"#))
    }

    // MARK: - benchmark.json producer

    @Test("--ab benchmark: canonical with_skill/without_skill rows, arm-marked per_eval, arm summaries + signed delta")
    func benchmarkTwoArms() {
        let withArm = [EvalResult(evalId: "a", trials: [trial(true, seconds: 3.0), trial(true, seconds: 3.0)])]
        let baseline = [EvalResult(evalId: "a", trials: [trial(false, seconds: 1.0), trial(false, exit: .polluted)])]
        let report = RunReport(skill: "demo", results: withArm, baseline: baseline)
        let bench = BenchmarkFile(skill: "demo", behavioral: (report: report, evals: withArm), baseline: baseline,
                                  trigger: nil, harness: "replay", k: 2, provenance: provenance, preserving: nil)
        let configs = bench.runs.compactMap { $0.objectValue?["configuration"]?.stringValue }
        #expect(configs.filter { $0 == "with_skill" }.count == 2)
        #expect(configs.filter { $0 == "without_skill" }.count == 1)   // the polluted trial writes no row
        #expect(!configs.contains("default"))

        let baseEntry = bench.fields["consistency"]?.objectValue?["per_eval"]?.arrayValue?
            .first { $0.objectValue?["arm"]?.stringValue == "baseline" }?.objectValue
        #expect(baseEntry?["runs"] == .number(1))
        #expect(baseEntry?["perfect_passes"] == .number(0))
        #expect(baseEntry?["polluted"] == .number(1))

        let summary = bench.runSummary
        #expect(summary?["with_skill"]?.objectValue?["pass_rate"]?.objectValue?["mean"] == .number(1))
        #expect(summary?["with_skill"]?.objectValue?["time_seconds"]?.objectValue?["mean"] == .number(3.0))
        #expect(summary?["without_skill"]?.objectValue?["pass_rate"]?.objectValue?["mean"] == .number(0))
        #expect(summary?["delta"]?.objectValue?["pass_rate"] == .string("+1.00"))
        #expect(summary?["delta"]?.objectValue?["time_seconds"] == .string("+2.0"))
        #expect(summary?["delta"]?.objectValue?["tokens"] == .string("+0"))

        // Recompute separation: the with-arm never mixes with the baseline arm.
        #expect(bench.evalCounts.map(\.recorded) == [2])
        #expect(bench.baselineCounts.map(\.recorded) == [1])
        #expect(bench.abPolluted == 1)
        #expect(bench.abTimeDelta == 2.0)
    }

    @Test("benchmark delta.pass_rate uses the PAIRED estimator, not pooled trial means (review finding)")
    func unevenMeasuredCountsPairedDelta() {
        // Uneven measured baseline counts (pollution hit only e2): paired and pooled diverge.
        //   e1: with 2/2 (rate 1.0) vs baseline 1/2 (rate 0.5) → Δ +0.5
        //   e2: with 1/2 (rate 0.5) vs baseline 0/1 measured (rate 0.0; 1 polluted) → Δ +0.5
        // Paired mean = +0.50. Pooled trial means: with (1+1+1+0)/4 = 0.75, baseline (1+0+0)/3 ≈ 0.333
        // → pooled ≈ +0.42 — the wrong number the producer used to write.
        let withArm = [
            EvalResult(evalId: "e1", trials: [trial(true), trial(true)]),
            EvalResult(evalId: "e2", trials: [trial(true), trial(false)])
        ]
        let baseline = [
            EvalResult(evalId: "e1", trials: [trial(true), trial(false)]),
            EvalResult(evalId: "e2", trials: [trial(false), trial(false, exit: .polluted)])
        ]
        let report = RunReport(skill: "demo", results: withArm, baseline: baseline)
        #expect(abs((report.ab?.pairedMeanDelta ?? 0) - 0.5) < 1e-9)
        let bench = BenchmarkFile(skill: "demo", behavioral: (report: report, evals: withArm), baseline: baseline,
                                  trigger: nil, harness: "replay", k: 2, provenance: provenance, preserving: nil)
        #expect(bench.runSummary?["delta"]?.objectValue?["pass_rate"] == .string("+0.50"))   // paired, matches skillet.run/1
    }

    @Test("The offline recompute rebuilds the ab block with the live math (P2/D3)")
    func offlineRebuild() throws {
        let withArm = [
            EvalResult(evalId: "a", trials: [trial(true), trial(true)]),
            EvalResult(evalId: "b", trials: [trial(true), trial(false)]),
            EvalResult(evalId: "c", trials: [trial(true)])
        ]
        let baseline = [
            EvalResult(evalId: "a", trials: [trial(false), trial(false)]),
            EvalResult(evalId: "b", trials: [trial(false), trial(false)]),
            EvalResult(evalId: "c", trials: [trial(false, exit: .polluted)])   // unmeasured pair
        ]
        let live = RunReport(skill: "demo", results: withArm, baseline: baseline)
        let bench = BenchmarkFile(skill: "demo", behavioral: (report: live, evals: withArm), baseline: baseline,
                                  trigger: nil, harness: "replay", k: 2, provenance: provenance, preserving: nil)
        let data = try JSONEncoder().encode(bench)   // round-trip through bytes like the real reader
        let rebuilt = RunReport(benchmark: try JSONDecoder().decode(BenchmarkFile.self, from: data))
        #expect(rebuilt.ab != nil)
        #expect(rebuilt.ab?.pairedMeanDelta == live.ab?.pairedMeanDelta)
        #expect(rebuilt.ab?.pairedSE == live.ab?.pairedSE)
        #expect(rebuilt.ab?.flipsUp == live.ab?.flipsUp)
        #expect(rebuilt.ab?.flipsDown == live.ab?.flipsDown)
        #expect(rebuilt.ab?.perEval == live.ab?.perEval)
        #expect(rebuilt.ab?.polluted == live.ab?.polluted)
        #expect(rebuilt.ab?.unmeasuredEvalIds == ["c"])   // the unmeasured pair survives the round-trip
        #expect(rebuilt.ab?.timeDeltaSeconds == live.ab?.timeDeltaSeconds)   // both nil here — optionality preserved
    }

    @Test("An unmeasured arm omits time_seconds and the delta block — mean([]) is not a measurement (review round 2)")
    func unmeasuredArmOmitsTimeAndDelta() throws {
        let withArm = [EvalResult(evalId: "e", trials: [trial(true, seconds: 3.0)])]
        let baseline = [EvalResult(evalId: "e", trials: [trial(false, exit: .polluted)])]   // every trial polluted
        let live = RunReport(skill: "demo", results: withArm, baseline: baseline)
        #expect(live.ab?.timeDeltaSeconds == nil)
        let bench = BenchmarkFile(skill: "demo", behavioral: (report: live, evals: withArm), baseline: baseline,
                                  trigger: nil, harness: "replay", k: 1, provenance: provenance, preserving: nil)
        #expect(bench.runSummary?["without_skill"]?.objectValue?["pass_rate"] != nil)
        #expect(bench.runSummary?["without_skill"]?.objectValue?["time_seconds"] == nil)   // unmeasured arm: key absent
        #expect(bench.runSummary?["delta"] == nil)   // no measured pair, no measured durations → no delta block
        #expect(bench.abTimeDelta == nil)
        let data = try JSONEncoder().encode(bench)
        let rebuilt = RunReport(benchmark: try JSONDecoder().decode(BenchmarkFile.self, from: data))
        #expect(rebuilt.ab?.timeDeltaSeconds == nil)   // the old code rebuilt a fabricated non-nil delta here
        #expect(rebuilt.ab?.unmeasuredEvalIds == ["e"])
    }

    @Test("A trigger-only run carries the prior AB record intact (rows, arm entries, summaries, delta)")
    func triggerOnlyCarriesABRecord() {
        let withArm = [EvalResult(evalId: "a", trials: [trial(true)])]
        let baseline = [EvalResult(evalId: "a", trials: [trial(false)])]
        let report = RunReport(skill: "demo", results: withArm, baseline: baseline)
        let prior = BenchmarkFile(skill: "demo", behavioral: (report: report, evals: withArm), baseline: baseline,
                                  trigger: nil, harness: "replay", k: 1, provenance: provenance, preserving: nil)
        let trigger = [TriggerEvalResult(evalId: "t0", query: "q", shouldTrigger: true,
                                         trials: [TriggerTrialResult(exit: .passed, firedTarget: true)])]
        let merged = BenchmarkFile(skill: "demo", behavioral: nil, trigger: trigger,
                                   harness: "replay", k: 1, provenance: provenance, preserving: prior)
        let configs = merged.runs.compactMap { $0.objectValue?["configuration"]?.stringValue }
        #expect(configs.contains("with_skill"))
        #expect(configs.contains("without_skill"))
        #expect(configs.contains("trigger"))
        #expect(merged.baselineCounts.count == 1)
        #expect(merged.runSummary?["with_skill"] != nil)
        #expect(merged.runSummary?["without_skill"] != nil)
        #expect(merged.runSummary?["delta"] != nil)
    }

    @Test("Single-arm runs keep configuration 'default' and run_summary.default (F7 shape unchanged)")
    func singleArmUnchanged() {
        let evals = [EvalResult(evalId: "a", trials: [trial(true)])]
        let bench = BenchmarkFile(report: RunReport(skill: "demo", results: evals), evals: evals,
                                  harness: "replay", k: 1, provenance: provenance)
        #expect(bench.runs.first?.objectValue?["configuration"] == .string("default"))
        #expect(bench.runSummary?["default"] != nil)
        #expect(bench.runSummary?["with_skill"] == nil)
        #expect(bench.baselineCounts.isEmpty)
        #expect(RunReport(benchmark: bench).ab == nil)
    }
}
