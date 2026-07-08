import Foundation

/// One judged criterion — a single `expected_behavior`/expectation line graded by a ``Judge``. Pure
/// (EDDCore); the effectful judge lives in JudgeKit. Carries the provenance the design requires so a
/// run is re-gradable and comparable across time (§9.4).
public struct Verdict: Codable, Sendable, Equatable {
    public let criterion: String
    public let passed: Bool
    public let rationale: String
    public let judgeId: String
    public let model: String
    public let judgePromptVersion: String

    public init(criterion: String, passed: Bool, rationale: String, judgeId: String, model: String, judgePromptVersion: String) {
        self.criterion = criterion
        self.passed = passed
        self.rationale = rationale
        self.judgeId = judgeId
        self.model = model
        self.judgePromptVersion = judgePromptVersion
    }
}

/// How a trial ended — the run-record **exit class** (design §10), first-class so aggregation can
/// tell measurement from noise. (F7 ships `passed`/`failed`/`timeout`; F15 adds `polluted` — a
/// baseline trial disqualified by the §9.2 tripwire, a skill fired where provably none may exist;
/// the `infra` class lands with the infra-retry classifier in F18.)
public enum TrialExit: String, Codable, Sendable, Equatable {
    case passed, failed, timeout, polluted
}

/// One trial of one eval: its per-criterion verdicts + exit class. A trial **passes iff** the exit
/// class is `passed` **and** every verdict passed.
public struct TrialResult: Codable, Sendable, Equatable {
    public let exit: TrialExit
    public let verdicts: [Verdict]
    /// Wall-clock seconds of the harness execution (F15 — feeds the canonical per-arm
    /// `time_seconds` stats). `nil` on records written before F15 (tolerant decode).
    public let durationSeconds: Double?

    public init(exit: TrialExit, verdicts: [Verdict], durationSeconds: Double? = nil) {
        self.exit = exit
        self.verdicts = verdicts
        self.durationSeconds = durationSeconds
    }

    /// Passes iff it ran cleanly, produced **at least one** verdict, and every verdict passed. The
    /// non-empty guard means a trial with no graded criteria never counts as a vacuous pass (a defense
    /// behind the pre-spend rejection of zero-expectation evals).
    public var passed: Bool { exit == .passed && !verdicts.isEmpty && verdicts.allSatisfy(\.passed) }
}

/// All recorded trials for one eval.
public struct EvalResult: Codable, Sendable, Equatable {
    public let evalId: String
    public let trials: [TrialResult]

    public init(evalId: String, trials: [TrialResult]) {
        self.evalId = evalId
        self.trials = trials
    }

    /// Trials actually recorded for this eval (may be < requested k if trials were lost).
    public var recorded: Int { trials.count }
    /// Recorded trials that fully passed.
    public var passes: Int { trials.filter(\.passed).count }
    /// Trials disqualified by the baseline pollution tripwire (F15) — never graded, never counted.
    public var polluted: Int { trials.filter { $0.exit == .polluted }.count }
    /// Recorded trials that were actually measured (everything except `polluted`).
    public var measured: Int { recorded - polluted }
}

/// An eval's `pass^k` verdict at its recorded trials (design §4 vocab).
public enum EvalStatus: String, Codable, Sendable, Equatable {
    case pass, fail, flaky
}

/// The pure `pass^k` math (constitution III): given per-eval (passes, recorded) — exactly what the
/// committed `benchmark.json` carries — it derives each eval's status and the aggregate, so the
/// baseline re-derives offline from committed records, not the gitignored cache (P2/D3).
public enum PassK {
    /// An eval **PASSes** iff every recorded trial passed (`passes == recorded`, recorded > 0);
    /// **FAILs** iff zero passed; **FLAKY** iff `0 < passes < recorded` — on the eval's *own*
    /// recorded count, never truncated to the run's observed k.
    public static func status(passes: Int, recorded: Int) -> EvalStatus {
        if recorded > 0 && passes == recorded { return .pass }
        if passes == 0 { return .fail }
        return .flaky
    }
}

/// The `--json` payload for `skillet run` (`skillet.run/1`): the run-level `observed_k` + aggregate
/// `pass^k`, with per-eval rows showing each eval's own `passes`/`recorded` and status. Built from a
/// live run's ``EvalResult``s, or **re-derived offline** from per-eval `(passes, recorded)` counts
/// (e.g. from the committed `benchmark.json`) — the authoritative recompute path.
public struct RunReport: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.run/1"

    public let skill: String
    /// `min` recorded-trial count across evals — the run-level basis for the aggregate.
    public let observedK: Int
    /// Fraction of evals that PASS. Meaningful only when `measurable` (observed k ≥ 2).
    public let passK: Double
    /// Mean per-eval trial pass rate (`passes/recorded`, averaged over evals) — τ-bench's headline
    /// `pass^1` (design §14-11, adopted 2026-07-01): the *comparability* number, well-defined even at
    /// k = 1. Additive in `skillet.run/1`; the strict all-trials `passK` stays the reliability gate
    /// (deliberately conservative vs τ-bench's unbiased estimator under mixed recorded counts).
    public let passOne: Double
    /// Whether `pass^k` is meaningful (observed k ≥ 2); below that, consistency is "unmeasurable".
    public let measurable: Bool
    public let evals: [Row]
    public let passed: Int
    public let flaky: Int
    public let failed: Int
    /// The trigger axis (F14), when it ran — additive within `skillet.run/1`; `nil` (key absent)
    /// means the axis did not run this invocation. The behavioral fields above keep their exact
    /// pre-F14 meaning.
    public let trigger: Axis?
    /// The A/B baseline comparison (F15), when `--ab` ran — additive; `nil` (key absent) on
    /// single-arm runs. The behavioral fields above are the WITH-skill arm, unchanged.
    public let ab: ABComparison?

    enum CodingKeys: String, CodingKey {
        case skill, observedK, passK, measurable, evals, passed, flaky, failed, trigger, ab
        case passOne = "pass_1"   // exact frozen spelling; the snake-case strategy leaves it unchanged
    }

    /// One axis's aggregate — the same math as the behavioral top level (observed k, strict
    /// `pass^k`, additive `pass_1`, FLAKY trichotomy), reused by the `trigger` block.
    public struct Axis: Codable, Sendable, Equatable {
        public let observedK: Int
        public let passK: Double
        public let passOne: Double
        public let measurable: Bool
        public let evals: [Row]
        public let passed: Int
        public let flaky: Int
        public let failed: Int

        enum CodingKeys: String, CodingKey {
            case observedK, passK, measurable, evals, passed, flaky, failed
            case passOne = "pass_1"
        }

        public init(counts: [(id: String, passes: Int, recorded: Int)]) {
            self.evals = counts.map { Row(id: $0.id, status: PassK.status(passes: $0.passes, recorded: $0.recorded), passes: $0.passes, recorded: $0.recorded) }
            self.observedK = counts.map(\.recorded).min() ?? 0
            self.passed = evals.filter { $0.status == .pass }.count
            self.flaky = evals.filter { $0.status == .flaky }.count
            self.failed = evals.filter { $0.status == .fail }.count
            self.passK = evals.isEmpty ? 0 : Double(passed) / Double(evals.count)
            self.passOne = evals.isEmpty ? 0 : evals
                .map { $0.recorded == 0 ? 0 : Double($0.passes) / Double($0.recorded) }
                .reduce(0, +) / Double(evals.count)
            self.measurable = observedK >= 2
        }
    }

    public struct Row: Codable, Sendable, Equatable {
        public let id: String
        public let status: EvalStatus
        public let passes: Int
        public let recorded: Int
        public init(id: String, status: EvalStatus, passes: Int, recorded: Int) {
            self.id = id
            self.status = status
            self.passes = passes
            self.recorded = recorded
        }
    }

    /// Build from a live run's full results (behavioral axis, plus the trigger axis when it ran,
    /// plus the baseline arm when `--ab` ran — F15).
    public init(skill: String, results: [EvalResult], trigger: [TriggerEvalResult]? = nil, baseline: [EvalResult]? = nil) {
        self.init(
            skill: skill,
            counts: results.map { (id: $0.evalId, passes: $0.passes, recorded: $0.recorded) },
            trigger: trigger.map { Axis(counts: $0.map { (id: $0.evalId, passes: $0.passes, recorded: $0.recorded) }) },
            ab: baseline.map { ABComparison(withArm: results, baseline: $0) }
        )
    }

    /// Build from per-eval `(passes, recorded)` — the offline recompute path (e.g. from `benchmark.json`).
    public init(skill: String, counts: [(id: String, passes: Int, recorded: Int)], trigger: Axis? = nil, ab: ABComparison? = nil) {
        self.skill = skill
        self.trigger = trigger
        self.ab = ab
        self.evals = counts.map { Row(id: $0.id, status: PassK.status(passes: $0.passes, recorded: $0.recorded), passes: $0.passes, recorded: $0.recorded) }
        self.observedK = counts.map(\.recorded).min() ?? 0
        self.passed = evals.filter { $0.status == .pass }.count
        self.flaky = evals.filter { $0.status == .flaky }.count
        self.failed = evals.filter { $0.status == .fail }.count
        self.passK = evals.isEmpty ? 0 : Double(passed) / Double(evals.count)
        self.passOne = evals.isEmpty ? 0 : evals
            .map { $0.recorded == 0 ? 0 : Double($0.passes) / Double($0.recorded) }
            .reduce(0, +) / Double(evals.count)
        self.measurable = observedK >= 2
    }
}

/// The A/B baseline block (F15) — additive in `skillet.run/1` when `--ab` ran. The report's
/// behavioral fields are the WITH-skill arm; this block carries the baseline arm and the **paired**
/// comparison: per-eval Δ first, then the mean of those Δs ± a standard error (Anthropic's
/// error-bars guidance — pairing cancels the arms' shared per-eval difficulty; never subtract two
/// marginal scores). Uncertainty is honest: below 2 paired evals the SE is absent, not invented.
public struct ABComparison: Codable, Sendable, Equatable {
    /// The baseline (without-skill) arm aggregate. `polluted` trials — the §9.2 tripwire fired: a
    /// skill invocation appeared where provably none may exist — are excluded from every count.
    public let baseline: RunReport.Axis
    public let perEval: [PairedRow]
    /// Mean of the per-eval paired deltas (with-arm trial pass rate − baseline trial pass rate).
    public let pairedMeanDelta: Double
    /// Bessel-corrected standard error of the per-eval deltas; `nil` below 2 paired evals.
    public let pairedSE: Double?
    /// Evals the skill flips to PASS (baseline non-PASS → with PASS) / breaks (PASS → non-PASS).
    public let flipsUp: Int
    public let flipsDown: Int
    /// Mean per-trial wall-clock delta in seconds (with − baseline); `nil` when either arm has no
    /// measured durations.
    public let timeDeltaSeconds: Double?
    /// Baseline trials disqualified by the pollution tripwire (never graded, never counted).
    public let polluted: Int
    /// Evals FLAKY in either arm — their Δ is hygiene-untrusted (§8) until stabilized.
    public let untrustedEvalIds: [String]
    /// Evals with zero **measured** trials in one arm (e.g. every baseline trial polluted, or a
    /// promptless with-arm): no Δ, no flip, excluded from the paired stats — absence of evidence
    /// must never manufacture a skill effect (review finding, 2026-07-07).
    public let unmeasuredEvalIds: [String]

    /// One eval, both arms, paired: statuses + counts in the run-table idiom, and the rate delta.
    public struct PairedRow: Codable, Sendable, Equatable {
        public let id: String
        public let withStatus: EvalStatus
        public let withPasses: Int
        public let withRecorded: Int
        public let baselineStatus: EvalStatus
        public let baselinePasses: Int
        /// Baseline trials actually measured (polluted excluded).
        public let baselineRecorded: Int
        /// with-arm trial pass rate − baseline trial pass rate; `nil` when either arm has zero
        /// measured trials — an unmeasured pair, never a fabricated ±1.00.
        public let delta: Double?

        public init(id: String, withStatus: EvalStatus, withPasses: Int, withRecorded: Int,
                    baselineStatus: EvalStatus, baselinePasses: Int, baselineRecorded: Int, delta: Double?) {
            self.id = id
            self.withStatus = withStatus
            self.withPasses = withPasses
            self.withRecorded = withRecorded
            self.baselineStatus = baselineStatus
            self.baselinePasses = baselinePasses
            self.baselineRecorded = baselineRecorded
            self.delta = delta
        }
    }

    /// One eval's paired counts — the single basis both builders share, so the live report and the
    /// offline `benchmark.json` recompute can never disagree on the paired math (P2/D3).
    public typealias Pair = (id: String, withPasses: Int, withRecorded: Int, basePasses: Int, baseRecorded: Int)

    /// The designated builder: measured-pair rules live HERE and only here. A pair counts toward
    /// Δ/flips/SE **iff both arms have measured trials**; anything else is `unmeasured` — reported,
    /// never averaged.
    public init(pairs: [Pair], timeDeltaSeconds: Double?, polluted: Int) {
        var rows: [PairedRow] = []
        var deltas: [Double] = []
        var up = 0
        var down = 0
        var untrusted: [String] = []
        var unmeasured: [String] = []
        var baseCounts: [(id: String, passes: Int, recorded: Int)] = []
        for pair in pairs {
            let withStatus = PassK.status(passes: pair.withPasses, recorded: pair.withRecorded)
            let baseStatus = PassK.status(passes: pair.basePasses, recorded: pair.baseRecorded)
            let measuredPair = pair.withRecorded > 0 && pair.baseRecorded > 0
            var delta: Double?
            if measuredPair {
                delta = Double(pair.withPasses) / Double(pair.withRecorded)
                    - Double(pair.basePasses) / Double(pair.baseRecorded)
                deltas.append(delta!)
                if baseStatus != .pass && withStatus == .pass { up += 1 }
                if baseStatus == .pass && withStatus != .pass { down += 1 }
                if withStatus == .flaky || baseStatus == .flaky { untrusted.append(pair.id) }
            } else {
                unmeasured.append(pair.id)
            }
            baseCounts.append((id: pair.id, passes: pair.basePasses, recorded: pair.baseRecorded))
            rows.append(PairedRow(
                id: pair.id, withStatus: withStatus, withPasses: pair.withPasses, withRecorded: pair.withRecorded,
                baselineStatus: baseStatus, baselinePasses: pair.basePasses, baselineRecorded: pair.baseRecorded, delta: delta
            ))
        }
        let (mean, se) = Self.pairedStats(deltas)
        self.baseline = RunReport.Axis(counts: baseCounts)
        self.perEval = rows
        self.pairedMeanDelta = mean
        self.pairedSE = se
        self.flipsUp = up
        self.flipsDown = down
        self.timeDeltaSeconds = timeDeltaSeconds
        self.polluted = polluted
        self.untrustedEvalIds = untrusted
        self.unmeasuredEvalIds = unmeasured
    }

    /// Build from a live run's two arms. Pairing is by eval id, in the with-arm's order; a baseline
    /// eval that never ran (or whose every trial was polluted) pairs as unmeasured.
    public init(withArm: [EvalResult], baseline: [EvalResult]) {
        let baseById = Dictionary(baseline.map { ($0.evalId, $0) }, uniquingKeysWith: { first, _ in first })
        let pairs: [Pair] = withArm.map { with in
            let clean = (baseById[with.evalId]?.trials ?? []).filter { $0.exit != .polluted }
            return (id: with.evalId, withPasses: with.passes, withRecorded: with.recorded,
                    basePasses: clean.filter(\.passed).count, baseRecorded: clean.count)
        }
        let withDurations = withArm.flatMap { $0.trials.compactMap(\.durationSeconds) }
        let baseDurations = baseline.flatMap { $0.trials.filter { $0.exit != .polluted }.compactMap(\.durationSeconds) }
        let timeDelta: Double? = (withDurations.isEmpty || baseDurations.isEmpty) ? nil
            : withDurations.reduce(0, +) / Double(withDurations.count)
                - baseDurations.reduce(0, +) / Double(baseDurations.count)
        self.init(pairs: pairs, timeDeltaSeconds: timeDelta, polluted: baseline.reduce(0) { $0 + $1.polluted })
    }

    /// The paired-difference estimator: mean of the per-eval deltas, with a Bessel-corrected
    /// standard error at n ≥ 2 (below that: `nil` — "too few to state uncertainty").
    public static func pairedStats(_ deltas: [Double]) -> (mean: Double, se: Double?) {
        guard !deltas.isEmpty else { return (0, nil) }
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        guard deltas.count >= 2 else { return (mean, nil) }
        let variance = deltas.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(deltas.count - 1)
        return (mean, (variance / Double(deltas.count)).squareRoot())
    }
}
