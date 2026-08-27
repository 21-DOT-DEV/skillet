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
    func pairedStats() throws {
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
    func liveComparison() throws {
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
        let ab = ABComparison(withArm: try UniqueByName(withArm, name: \.evalId), baseline: try UniqueByName(baseline, name: \.evalId))
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
    func missingBaselinePairIsUnmeasured() throws {
        let ab = ABComparison(
            withArm: try UniqueByName([EvalResult(evalId: "only-with", trials: [trial(true)])], name: \.evalId),
            baseline: try UniqueByName([EvalResult](), name: \.evalId))
        #expect(ab.perEval[0].baselineRecorded == 0)
        #expect(ab.perEval[0].delta == nil)
        #expect(ab.unmeasuredEvalIds == ["only-with"])
        #expect(ab.flipsUp == 0)
        #expect(ab.pairedMeanDelta == 0)   // no measured deltas — nothing to average
        #expect(ab.pairedSE == nil)
    }

    @Test("An entirely polluted baseline manufactures NO skill effect (review finding, 2026-07-07)")
    func allPollutedBaselineNoFakeEffect() throws {
        let withArm = [EvalResult(evalId: "e", trials: [trial(true)])]
        let baseline = [EvalResult(evalId: "e", trials: [trial(false, exit: .polluted), trial(false, exit: .polluted)])]
        let ab = ABComparison(withArm: try UniqueByName(withArm, name: \.evalId), baseline: try UniqueByName(baseline, name: \.evalId))
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
        let ab = try SkilletJSON.encode(try RunReport(skill: "demo", results: withArm, baseline: baseline))
        #expect(ab.contains(#""ab":"#))
        #expect(ab.contains(#""paired_mean_delta""#))
        #expect(ab.contains(#""flips_up""#))
        #expect(ab.contains(#""pass_1""#))
        let single = try SkilletJSON.encode(try RunReport(skill: "demo", results: withArm))
        #expect(!single.contains(#""ab":"#))
    }

    // MARK: - benchmark.json producer

    @Test("--ab benchmark: canonical with_skill/without_skill rows, arm-marked per_eval, arm summaries + signed delta")
    func benchmarkTwoArms() throws {
        let withArm = [EvalResult(evalId: "a", trials: [trial(true, seconds: 3.0), trial(true, seconds: 3.0)])]
        let baseline = [EvalResult(evalId: "a", trials: [trial(false, seconds: 1.0), trial(false, exit: .polluted)])]
        let report = try RunReport(skill: "demo", results: withArm, baseline: baseline)
        let bench = try BenchmarkFile(skill: "demo", behavioral: (report: report, evals: withArm), baseline: baseline,
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
        // **Nothing counted tokens, so the file says nothing about them.** This used to assert a zero
        // difference — a made-up observation sitting where a real one would go, in a file whose own rule
        // is that a key appears only when the quantity was measured. Elapsed time has always followed
        // that rule by being left out; tokens were the lone exception.
        #expect(summary?["delta"]?.objectValue?["tokens"] == nil)

        // Recompute separation: the with-arm never mixes with the baseline arm.
        #expect(try bench.evalCounts.map(\.graded) == [2])
        #expect(try bench.baselineCounts.map(\.graded) == [1])
        #expect(try bench.abPolluted == 1)
        #expect(bench.abTimeDelta == 2.0)
    }

    @Test("benchmark delta.pass_rate uses the PAIRED estimator, not pooled trial means (review finding)")
    func unevenMeasuredCountsPairedDelta() throws {
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
        let report = try RunReport(skill: "demo", results: withArm, baseline: baseline)
        #expect(abs((report.ab?.pairedMeanDelta ?? 0) - 0.5) < 1e-9)
        let bench = try BenchmarkFile(skill: "demo", behavioral: (report: report, evals: withArm), baseline: baseline,
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
        let live = try RunReport(skill: "demo", results: withArm, baseline: baseline)
        let bench = try BenchmarkFile(skill: "demo", behavioral: (report: live, evals: withArm), baseline: baseline,
                                  trigger: nil, harness: "replay", k: 2, provenance: provenance, preserving: nil)
        let data = try JSONEncoder().encode(bench)   // round-trip through bytes like the real reader
        let rebuilt = try RunReport(benchmark: try JSONDecoder().decode(BenchmarkFile.self, from: data))
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
        let live = try RunReport(skill: "demo", results: withArm, baseline: baseline)
        #expect(live.ab?.timeDeltaSeconds == nil)
        let bench = try BenchmarkFile(skill: "demo", behavioral: (report: live, evals: withArm), baseline: baseline,
                                  trigger: nil, harness: "replay", k: 1, provenance: provenance, preserving: nil)
        // **The score is absent too, and this line used to assert the opposite.** The test is named for
        // the rule that an average of nothing is not a measurement, and then required the score to be
        // written anyway — so a run whose every attempt was disqualified recorded a score of zero,
        // indistinguishable from one that genuinely got everything wrong, and reading as the most
        // flattering possible result for the skill: "without it, nothing worked."
        #expect(bench.runSummary?["without_skill"]?.objectValue?["pass_rate"] == nil)
        #expect(bench.runSummary?["without_skill"]?.objectValue?["time_seconds"] == nil)   // unmeasured arm: key absent
        #expect(bench.runSummary?["delta"] == nil)   // no measured pair, no measured durations → no delta block
        #expect(bench.abTimeDelta == nil)
        let data = try JSONEncoder().encode(bench)
        let rebuilt = try RunReport(benchmark: try JSONDecoder().decode(BenchmarkFile.self, from: data))
        #expect(rebuilt.ab?.timeDeltaSeconds == nil)   // the old code rebuilt a fabricated non-nil delta here
        #expect(rebuilt.ab?.unmeasuredEvalIds == ["e"])
    }

    @Test("A trigger-only run carries the prior AB record intact (rows, arm entries, summaries, delta)")
    func triggerOnlyCarriesABRecord() throws {
        let withArm = [EvalResult(evalId: "a", trials: [trial(true)])]
        let baseline = [EvalResult(evalId: "a", trials: [trial(false)])]
        let report = try RunReport(skill: "demo", results: withArm, baseline: baseline)
        let prior = try BenchmarkFile(skill: "demo", behavioral: (report: report, evals: withArm), baseline: baseline,
                                  trigger: nil, harness: "replay", k: 1, provenance: provenance, preserving: nil)
        let trigger = [TriggerEvalResult(evalId: "t0", query: "q", shouldTrigger: true,
                                         trials: [TriggerTrialResult(exit: .passed, firedTarget: true)])]
        let merged = try BenchmarkFile(skill: "demo", behavioral: nil, trigger: trigger,
                                   harness: "replay", k: 1, provenance: provenance, preserving: prior)
        let configs = merged.runs.compactMap { $0.objectValue?["configuration"]?.stringValue }
        #expect(configs.contains("with_skill"))
        #expect(configs.contains("without_skill"))
        #expect(configs.contains("trigger"))
        #expect(try merged.baselineCounts.count == 1)
        #expect(merged.runSummary?["with_skill"] != nil)
        #expect(merged.runSummary?["without_skill"] != nil)
        #expect(merged.runSummary?["delta"] != nil)
    }

    @Test("Single-arm runs keep configuration 'default' and run_summary.default (F7 shape unchanged)")
    func singleArmUnchanged() throws {
        let evals = [EvalResult(evalId: "a", trials: [trial(true)])]
        let bench = try BenchmarkFile(report: try RunReport(skill: "demo", results: evals), evals: evals,
                                  harness: "replay", k: 1, provenance: provenance)
        #expect(bench.runs.first?.objectValue?["configuration"] == .string("default"))
        #expect(bench.runSummary?["default"] != nil)
        #expect(bench.runSummary?["with_skill"] == nil)
        #expect(try bench.baselineCounts.isEmpty)
        #expect(try RunReport(benchmark: bench).ab == nil)
    }

    /// **A run with one arm summarises the same fields as a run with two.** How long trials took is
    /// measured either way, and used to be recorded either way in the per-trial rows — but the aggregate
    /// dropped it whenever there was no second arm to compare against. So a chart of how long a suite
    /// takes got its numbers from comparison runs and nothing at all from plain ones, with no signal that
    /// anything was missing. One builder now produces every arm block, so a field cannot be present on
    /// one and quietly absent from its sibling.
    @Test("A single-arm summary reports the same fields as a two-arm one")
    func singleArmSummaryHasTheSameFields() throws {
        let evals = [EvalResult(evalId: "a", trials: [trial(true, seconds: 1.5), trial(true, seconds: 2.5)])]
        let bench = try BenchmarkFile(report: try RunReport(skill: "demo", results: evals), evals: evals,
                                      harness: "replay", k: 2, provenance: provenance)
        let single = try #require(bench.runSummary?["default"]?.objectValue)

        let baseline = [EvalResult(evalId: "a", trials: [trial(false, seconds: 1.0)])]
        let paired = try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: evals, baseline: baseline), evals: evals),
            baseline: baseline, trigger: nil, harness: "replay", k: 2, provenance: provenance, preserving: nil)
        let withArm = try #require(paired.runSummary?["with_skill"]?.objectValue)
        #expect(Set(single.keys) == Set(withArm.keys),
                "one arm or two, the same measurements were taken — so the same fields are reported")
        #expect(!single.keys.contains("tokens"),
                "nothing counted tokens on this run, so the file claims nothing about them")

        // Named directly as well, so the agreement above cannot be satisfied by both sides losing it.
        #expect(single["time_seconds"]?.objectValue?["mean"] == .number(2.0),
                "the average of a 1.5-second trial and a 2.5-second one")
    }
}

/// **Every figure in one report must count the same attempts.**
///
/// An attempt that was never graded stopped counting toward the headline score, but six other places went
/// on treating it as a graded attempt worth zero. Measured, for a check with two passing attempts and one
/// never graded: the headline said the skill passed outright while the before-and-after comparison said
/// two-thirds, reported three attempts where two were graded, and — worst — **did not notice the skill had
/// fixed the check at all**, because a two-thirds rate no longer counts as passing.
///
/// The rule now lives in one place and every score is built from a record rather than from numbers passed
/// by hand, so a caller cannot supply the total by mistake. This test exists because the failure was not
/// that anyone misunderstood the rule — it was that nothing noticed when two places disagreed.
@Suite("Every figure in a report counts the same attempts")
struct SameAttemptsEverywhereTests {
    private func verdict(_ passed: Bool) -> Verdict {
        Verdict(criterion: "a", passed: passed, rationale: "", judgeId: "t", model: "m", judgePromptVersion: "1")
    }
    private func attempt(_ exit: TrialExit, passed: Bool) -> TrialResult {
        TrialResult(exit: exit, verdicts: passed ? [verdict(true)] : (exit == .error ? [] : [verdict(false)]),
                    durationSeconds: 1, tokens: TokenCounts(uncachedInput: 10, output: 10))
    }

    @Test("Two passing attempts and one never graded read the same everywhere")
    func oneUngradedAttemptAgreesEverywhere() throws {
        let withSkill = [EvalResult(evalId: "e", trials: [
            attempt(.passed, passed: true), attempt(.passed, passed: true), attempt(.error, passed: false)])]
        let without = [EvalResult(evalId: "e", trials: [attempt(.failed, passed: false)])]
        let report = try RunReport(skill: "demo", results: withSkill, baseline: without)
        let comparison = try #require(report.ab)

        #expect(report.passK == 1.0, "every graded attempt passed")
        #expect(comparison.perEval[0].withRecorded == 2, "two attempts were graded, not three")
        #expect(comparison.pairedMeanDelta == 1.0, "the comparison must agree with the headline, not say 0.667")
        #expect(comparison.flipsUp == 1,
                "the skill turned a failing check into a passing one, which used to go unnoticed")
        #expect(report.ungraded == 1, "and the attempt that was lost is still stated")
    }

    /// The softer average used to give a check that measured nothing a flat zero while still dividing by
    /// every check, so one unmeasurable check dragged a working skill down.
    @Test("A check that measured nothing leaves the softer average, and the basis is published")
    func unmeasuredCheckLeavesTheAverage() throws {
        let measured = EvalResult(evalId: "a", trials: [attempt(.passed, passed: true)])
        let ungraded = EvalResult(evalId: "b", trials: [attempt(.error, passed: false)])
        let report = try RunReport(skill: "demo", results: [measured, ungraded])
        #expect(report.passOne == 1.0, "the one check that was measured passed")
        #expect(report.passOneEvals == 1, "and the figure says how many checks it covers")
    }
}
