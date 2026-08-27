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
/// baseline trial disqualified by the §9.2 tripwire, a skill fired where provably none may exist.)
///
/// **`error` means nothing was ever graded, so there is nothing to say about the skill.** It used to be
/// recorded as `failed`, which claims the opposite: that the skill was measured and did badly. So a
/// rate limit, a dropped connection, or the program running the model falling over was written down as
/// the skill getting worse — on ordinary paid runs, not in some corner case.
///
/// **The line between `failed` and `error` is the one every major test runner draws, and it needs no
/// judgement about causes.** A check that ran and came out negative is a failure; anything that stopped
/// the check running is an error. Nothing here decides whether the cause was "infrastructure" — a
/// distinction the tool cannot actually establish, which is why the name says only what is known.
///
/// `timeout` stays separate and still counts as a real result: a run that exceeded its time limit did
/// tell you something about the skill. Retrying an `error` automatically is a later phase (`F18`); this
/// only stops the wrong thing being recorded in the meantime.
public enum TrialExit: String, Codable, Sendable, Equatable {
    case passed, failed, timeout, polluted, error
}

/// One trial of one eval: its per-criterion verdicts + exit class. A trial **passes iff** the exit
/// class is `passed` **and** every verdict passed.
public struct TrialResult: Codable, Sendable, Equatable {
    public let exit: TrialExit
    public let verdicts: [Verdict]
    /// Wall-clock seconds of the harness execution (F15 — feeds the canonical per-arm
    /// `time_seconds` stats). `nil` on records written before F15 (tolerant decode).
    public let durationSeconds: Double?
    /// What this attempt read and wrote, when the tool that ran it reported counts. `nil` means nothing
    /// counted — an offline stand-in that was told nothing, or a record written before counting existed
    /// (tolerant decode, same as `durationSeconds` above). Absent from the results file rather than
    /// written as zeros, because a zero reads as a measurement and this is the absence of one.
    public let tokens: TokenCounts?
    /// **Whether an absent cost figure means "none reported" or "reported and unusable".** Both leave
    /// ``tokens`` empty, on purpose, so a part-read figure never enters a total — but only one of them is
    /// a problem someone would want to know about, and until now nothing carried which it was. `false` on
    /// every ordinary attempt, including the offline stand-ins that report no figures at all.
    public let tokensUnreadable: Bool

    public init(exit: TrialExit, verdicts: [Verdict], durationSeconds: Double? = nil,
                tokens: TokenCounts? = nil, tokensUnreadable: Bool = false) {
        self.exit = exit
        self.verdicts = verdicts
        self.durationSeconds = durationSeconds
        self.tokens = tokens
        self.tokensUnreadable = tokensUnreadable
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
    /// **Trials where grading never happened at all** — the grader errored, a rate limit hit, the
    /// connection dropped, the program running the model fell over. Counted so the loss is visible
    /// rather than inferred from a rate that quietly dropped.
    public var errored: Int { trials.filter { $0.exit == .error }.count }
    /// Recorded trials that were actually measured — neither disqualified nor left ungraded.
    ///
    /// **Leaving the ungraded ones in the total is a named statistical mistake, not a neutral default.**
    /// Treating a missing observation as a negative result is called non-responder imputation, and it is
    /// documented as strongly biasing the answer downward and, where the losses fall unevenly on the two
    /// things being compared, distorting the difference between them — which is the number this tool
    /// exists to produce. Analysing only what was actually observed is unbiased as long as the losses are
    /// unrelated to the outcome, which covers rate limits and dropped connections. ``errored`` is
    /// reported per arm so that uneven loss, the case where that assumption fails, is visible.
    public var measured: Int { recorded - polluted - errored }
}

/// An eval's `pass^k` verdict at its recorded trials (design §4 vocab).
public enum EvalStatus: String, Codable, Sendable, Equatable {
    case pass, fail, flaky
}

/// **The counts a score is computed from — graded attempts, never the total attempted.**
///
/// This exists because the rule "an attempt that was never graded does not count" was written as a plain
/// number passed around by hand, and eight separate places computed it. When the rule changed, two were
/// updated and six were not, so one report stated two contradicting scores for the same run and a
/// before-and-after comparison stopped noticing that a skill had fixed a check.
///
/// A plain number standing in for a domain idea is what forces that kind of scattered edit; naming the
/// idea and building it from the record itself is the standard remedy. The two initialisers below take a
/// whole record and derive the number, so the total attempted is not something a caller can pass by
/// mistake. The third takes the numbers directly and is for one job only — re-deriving a score from a
/// saved file, where the separation was already made when the file was written.
public struct EvalCounts: Sendable, Equatable {
    public let id: String
    public let passes: Int
    /// Attempts that produced a result. Never the number attempted.
    public let graded: Int

    public init(_ result: EvalResult) {
        self.init(id: result.evalId, passes: result.passes, graded: result.measured)
    }

    public init(_ result: TriggerEvalResult) {
        self.init(id: result.evalId, passes: result.passes, graded: result.measured)
    }

    /// **Only for re-deriving from a saved file.** Everywhere a live run is being summarised, use one of
    /// the initialisers above so the number cannot be the total by accident.
    public init(id: String, passes: Int, graded: Int) {
        self.id = id
        self.passes = passes
        self.graded = graded
    }
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
public struct RunReport: SchemaIdentified, Decodable, Sendable, Equatable {
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
    /// **How many checks the softer average above actually covers.**
    ///
    /// A check that measured nothing used to contribute a flat zero to that average while still counting
    /// in the divisor, so one unmeasurable check made a working skill look worse. Those checks are now
    /// left out — which would quietly shrink the basis of the figure without saying so, hence this count.
    /// Equal to the number of checks on an ordinary run.
    public let passOneEvals: Int
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
    /// **How many attempts reported what they cost in a form that could not be used.**
    ///
    /// The counts are dropped for those attempts on purpose, so a part-read figure never enters a total.
    /// But dropping them silently makes an unusable report look exactly like no report at all — and one of
    /// those is worth investigating. `0` on every ordinary run, including offline ones that report no
    /// figures at all.
    public let costUnreadable: Int
    /// **How many attempts never produced a result**, across every check that ran.
    ///
    /// Those attempts are left out of the scores above rather than counted as failures, so this number is
    /// what tells you the scores rest on fewer attempts than were asked for. Without it the loss is
    /// invisible: the rate simply comes from a smaller pool and nothing says so. `0` on any run where
    /// everything was graded, which is almost all of them.
    public let ungraded: Int

    enum CodingKeys: String, CodingKey {
        case skill, observedK, passK, measurable, evals, passed, flaky, failed, trigger, ab, ungraded
        // No spelling of its own: the ordinary conversion already writes it as `cost_unreadable` and reads
        // it back. Giving it one stopped it being read back at all, because the reader looks for the name
        // the conversion produces, not the one written here.
        case costUnreadable
        case passOne = "pass_1"
        case passOneEvals = "pass_1_evals"   // exact frozen spelling; the snake-case strategy leaves it unchanged
    }

    /// One axis's aggregate — the same math as the behavioral top level (observed k, strict
    /// `pass^k`, additive `pass_1`, FLAKY trichotomy), reused by the `trigger` block.
    public struct Axis: Codable, Sendable, Equatable {
        public let observedK: Int
        public let passK: Double
        public let passOne: Double
        /// How many checks ``passOne`` covers — see the same field on the enclosing report.
        public let passOneEvals: Int
        public let measurable: Bool
        public let evals: [Row]
        public let passed: Int
        public let flaky: Int
        public let failed: Int

        enum CodingKeys: String, CodingKey {
            case observedK, passK, measurable, evals, passed, flaky, failed
            case passOne = "pass_1"
            case passOneEvals = "pass_1_evals"
        }

        /// Same rule as the enclosing report: the figures are rebuilt from the rows rather than taken
        /// from the text, so the two cannot disagree.
        public init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            // Same refusal as the enclosing report: a repeated name is refused, not scored twice.
            let rows = try UniqueByName(try box.decode([Row].self, forKey: .evals), name: \.id).items
            self.init(counts: rows.map { EvalCounts(id: $0.id, passes: $0.passes, graded: $0.recorded) })
        }

        public init(counts: [EvalCounts]) {
            self.evals = counts.map { Row(id: $0.id, status: PassK.status(passes: $0.passes, recorded: $0.graded), passes: $0.passes, recorded: $0.graded) }
            self.observedK = counts.map(\.graded).min() ?? 0
            self.passed = evals.filter { $0.status == .pass }.count
            self.flaky = evals.filter { $0.status == .flaky }.count
            self.failed = evals.filter { $0.status == .fail }.count
            self.passK = evals.isEmpty ? 0 : Double(passed) / Double(evals.count)
            let counted = evals.filter { $0.recorded > 0 }
            self.passOneEvals = counted.count
            self.passOne = counted.isEmpty ? 0 : counted
                .map { Double($0.passes) / Double($0.recorded) }
                .reduce(0, +) / Double(counted.count)
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
    ///
    /// **Throws when *any* arm names one test twice.** This is the point at which a live run turns raw
    /// results into something a comparison can join on, so it is where the key's promise is made — and
    /// the promise has to cover every arm. Only the without-skill arm used to be checked, on the
    /// reasoning that it is the side looked up and the others are merely walked in order. Walking a
    /// repeat is not harmless: measured directly, three results for two distinct tests produced a report
    /// claiming three tests, and a comparison that paired the *same* without-skill result against both
    /// copies, so one result counted twice in the average. The saved-file path was corrected earlier; the
    /// live path was left inconsistent with it, which is the shape this project keeps finding.
    ///
    /// **It throws the plain repeat, not a bad-file report — deliberately, and unlike the saved-file
    /// path.** That path is reading a file that may be old or hand-edited, so the file is at fault and is
    /// named. Here the results were handed in by the caller, so no file can honestly be blamed, and
    /// claiming one would send a reader to look at something that is fine.
    ///
    /// **What that means for someone running the command, since the two paths end differently.** A
    /// repeated name in a saved file ends as "that file is not valid", naming the file and how to fix it.
    /// A repeated name here ends as "this is a defect in skillet, not a problem with your project",
    /// carrying the same sentence about which name repeated and a link to report it. That is the right
    /// answer rather than an oversight: the names a run reports come either from a check that already
    /// refused repeats before any money was spent, naming the file and the fix, or from numbering
    /// generated in a loop. So a repeat arriving *here* means one of those two failed, which is this
    /// tool's fault and not the project's. Pinned by a test, so the classification cannot drift quietly.
    public init(skill: String, results: [EvalResult], trigger: [TriggerEvalResult]? = nil,
                baseline: [EvalResult]? = nil) throws {
        let withArm = try UniqueByName(results, name: \.evalId)
        let triggerArm = try trigger.map { try UniqueByName($0, name: \.evalId) }
        self.init(
            skill: skill,
            // **The denominator is what was graded, not what was attempted.** Counting an ungraded attempt
            // as a failure is a named statistical mistake — see ``EvalResult/measured`` — and it is what
            // turned a rate limit into a recorded regression.
            counts: withArm.items.map(EvalCounts.init),
            trigger: triggerArm.map { Axis(counts: $0.items.map(EvalCounts.init)) },
            ab: try baseline.map { ABComparison(withArm: withArm, baseline: try UniqueByName($0, name: \.evalId)) },
            costUnreadable: withArm.items.reduce(0) { $0 + $1.trials.filter(\.tokensUnreadable).count }
                + (baseline?.reduce(0) { $0 + $1.trials.filter(\.tokensUnreadable).count } ?? 0),
            ungraded: withArm.items.reduce(0) { $0 + $1.errored }
                + (triggerArm?.items.reduce(0) { $0 + $1.errored } ?? 0)
                + (baseline?.reduce(0) { $0 + $1.errored } ?? 0)
        )
    }

    /// Build from per-eval `(passes, recorded)` — the offline recompute path (e.g. from `benchmark.json`).
    /// **Read back by rebuilding, not by believing the text.** Every figure above — the repeats observed,
    /// both headline scores, the counts of passing, flaky and failing checks — is worked out from the rows
    /// when a report is made. Left to a generated reader they would simply be taken from the file, so a
    /// hand-edited or truncated one could state a score its own rows contradict. This hands the rows back
    /// to the same initialiser that built them, so reading cannot reach a different answer from writing.
    ///
    /// This also makes the published output readable at all: the type could not be decoded before, so
    /// nothing could consume what this tool writes — the contract was one-way.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        // **A repeated check name is refused here as it is everywhere else.** Both other ways of building
        // a report throw on one; reading a published one accepted it silently and worked out a score from
        // the repeated rows, making the published format the most permissive of the three when it is meant
        // to mirror them.
        let rows = try UniqueByName(try box.decode([Row].self, forKey: .evals), name: \.id).items
        self.init(
            skill: try box.decode(String.self, forKey: .skill),
            counts: rows.map { EvalCounts(id: $0.id, passes: $0.passes, graded: $0.recorded) },
            trigger: try box.decodeIfPresent(Axis.self, forKey: .trigger),
            ab: try box.decodeIfPresent(ABComparison.self, forKey: .ab),
            costUnreadable: try box.decodeIfPresent(Int.self, forKey: .costUnreadable) ?? 0,
            ungraded: try box.decodeIfPresent(Int.self, forKey: .ungraded) ?? 0)
    }

    public init(skill: String, counts: [EvalCounts], trigger: Axis? = nil,
                ab: ABComparison? = nil, costUnreadable: Int = 0, ungraded: Int = 0) {
        self.skill = skill
        self.trigger = trigger
        self.ab = ab
        self.costUnreadable = costUnreadable
        self.ungraded = ungraded
        self.evals = counts.map { Row(id: $0.id, status: PassK.status(passes: $0.passes, recorded: $0.graded), passes: $0.passes, recorded: $0.graded) }
        self.observedK = counts.map(\.graded).min() ?? 0
        self.passed = evals.filter { $0.status == .pass }.count
        self.flaky = evals.filter { $0.status == .flaky }.count
        self.failed = evals.filter { $0.status == .fail }.count
        self.passK = evals.isEmpty ? 0 : Double(passed) / Double(evals.count)
        let counted = evals.filter { $0.recorded > 0 }
        self.passOneEvals = counted.count
        self.passOne = counted.isEmpty ? 0 : counted
            .map { Double($0.passes) / Double($0.recorded) }
            .reduce(0, +) / Double(counted.count)
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
    /// **How many more tokens the model read and wrote per attempt, with the skill than without it.**
    /// `nil` when either side counted nothing. Everything the model handled, so it means the same whether
    /// or not the provider's cache happened to be warm; the cached-versus-fresh split is reported per run
    /// and never as a difference, because that split moves on timing luck rather than on the skill.
    ///
    /// Carried here so the printed summary can state it. It was being written into the saved file and
    /// read back by nothing, while the line that would show it printed a dash — a number promised by the
    /// record that no reader could obtain.
    public let tokenDeltaPerAttempt: Double?
    /// Baseline trials disqualified by the pollution tripwire (never graded, never counted).
    public let polluted: Int
    /// Evals FLAKY in either arm — their Δ is hygiene-untrusted (§8) until stabilized.
    public let untrustedEvalIds: [String]
    /// Evals with zero **measured** trials in one arm (e.g. every baseline trial polluted, or a
    /// promptless with-arm): no Δ, no flip, excluded from the paired stats — absence of evidence
    /// must never manufacture a skill effect (review finding, 2026-07-07).
    public let unmeasuredEvalIds: [String]

    /// **No comparison was drawn at all** — every pairing came back unmeasured. Distinct from "the
    /// comparison came out flat": there is nothing here to read, so the numbers above carry no meaning.
    /// Lives beside the data rather than inside the command that acts on it, so the definition of "no
    /// comparison" and the decision taken on it cannot drift apart, and so it can be tested directly —
    /// the offline stand-ins cannot produce a polluted baseline, so this state is unreachable from an
    /// end-to-end test.
    public var producedNoPairing: Bool {
        !perEval.isEmpty && unmeasuredEvalIds.count == perEval.count
    }

    /// One eval, both arms, paired: statuses + counts in the run-table idiom, and the rate delta.
    public struct PairedRow: Codable, Sendable, Equatable {
        public let id: String
        public let withStatus: EvalStatus
        public let withPasses: Int
        public let withRecorded: Int
        public let baselineStatus: EvalStatus
        public let baselinePasses: Int
        /// Attempts on the without-skill side that produced a result — neither thrown out because a
        /// skill fired where none may exist, nor left ungraded because nothing could be measured.
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
    /// **Read back by rebuilding, like the report that holds it.** Every summary figure here — the
    /// average difference, its spread, the tallies of checks the skill fixed and broke, and each row's own
    /// difference — is worked out from the paired counts when a comparison is made. Left to a generated
    /// reader they were simply taken from the text, so a published report could state that a skill fixed
    /// ninety-nine checks while the rows beside it showed one. Measured before this: tampering with that
    /// tally and reading the file back returned the tampered number.
    ///
    /// What is genuinely stored, because nothing here can derive it from the counts: how much longer the
    /// runs took, what they cost, and how many attempts were thrown out.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try box.decode([PairedRow].self, forKey: .perEval)
        self.init(
            pairs: rows.map { (id: $0.id, withPasses: $0.withPasses, withRecorded: $0.withRecorded,
                               basePasses: $0.baselinePasses, baseRecorded: $0.baselineRecorded) },
            timeDeltaSeconds: try box.decodeIfPresent(Double.self, forKey: .timeDeltaSeconds),
            polluted: try box.decodeIfPresent(Int.self, forKey: .polluted) ?? 0,
            tokenDeltaPerAttempt: try box.decodeIfPresent(Double.self, forKey: .tokenDeltaPerAttempt))
    }

    public init(pairs: [Pair], timeDeltaSeconds: Double?, polluted: Int,
                tokenDeltaPerAttempt: Double? = nil) {
        self.tokenDeltaPerAttempt = tokenDeltaPerAttempt
        var rows: [PairedRow] = []
        var deltas: [Double] = []
        var up = 0
        var down = 0
        var untrusted: [String] = []
        var unmeasured: [String] = []
        var baseCounts: [EvalCounts] = []
        for pair in pairs {
            let withStatus = PassK.status(passes: pair.withPasses, recorded: pair.withRecorded)
            let baseStatus = PassK.status(passes: pair.basePasses, recorded: pair.baseRecorded)
            let measuredPair = pair.withRecorded > 0 && pair.baseRecorded > 0
            // Worked out once and used where it is known to exist, rather than asserted to exist a line
            // later — the only such assertion in this path, and the surrounding code avoids them.
            let delta: Double? = measuredPair
                ? Double(pair.withPasses) / Double(pair.withRecorded)
                    - Double(pair.basePasses) / Double(pair.baseRecorded)
                : nil
            if let delta {
                deltas.append(delta)
                if baseStatus != .pass && withStatus == .pass { up += 1 }
                if baseStatus == .pass && withStatus != .pass { down += 1 }
                if withStatus == .flaky || baseStatus == .flaky { untrusted.append(pair.id) }
            } else {
                unmeasured.append(pair.id)
            }
            baseCounts.append(EvalCounts(id: pair.id, passes: pair.basePasses, graded: pair.baseRecorded))
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
    ///
    /// **Both arms are sets in which no name repeats, and neither can be anything else.** Only the
    /// looked-up side used to carry that guarantee, on the reasoning that the other is merely walked in
    /// order — but walking a repeat pairs the *same* looked-up result against both copies, so it counts
    /// twice in the average while the reader sees two rows that look independent. Taking the guarantee
    /// as a parameter rather than checking for it here means a caller cannot hand over a repeat at all,
    /// so there is no branch to forget: the order the arm was measured in is still preserved.
    public init(withArm: UniqueByName<EvalResult>, baseline: UniqueByName<EvalResult>) {
        let baseById = baseline
        // **Both sides count graded attempts only.** The with-skill side counted every attempt and the
        // without-skill side counted everything except the thrown-out ones, so an attempt that was never
        // graded was averaged in as a zero on both. Measured: one ungraded attempt turned a skill that
        // fixed a check into no detected improvement at all, while the headline figure in the same report
        // correctly said it passed.
        let pairs: [Pair] = withArm.items.map { with in
            let base = baseById[with.evalId]
            return (id: with.evalId, withPasses: with.passes, withRecorded: with.measured,
                    basePasses: base?.passes ?? 0, baseRecorded: base?.measured ?? 0)
        }
        let withDurations = withArm.items.flatMap { $0.trials.compactMap(\.durationSeconds) }
        let baseDurations = baseline.items.flatMap { $0.trials.filter { $0.exit != .polluted }.compactMap(\.durationSeconds) }
        let timeDelta: Double? = (withDurations.isEmpty || baseDurations.isEmpty) ? nil
            : withDurations.reduce(0, +) / Double(withDurations.count)
                - baseDurations.reduce(0, +) / Double(baseDurations.count)
        // Same shape as the wall-clock difference beside it, and the same rule: a difference needs both
        // sides to have counted, and it is averaged per attempt because a total would move with how many
        // attempts each side recorded — and the without-skill side records fewer whenever one is thrown out.
        let withTokens = withArm.items.flatMap { $0.trials.compactMap(\.tokens) }.map { Double($0.total) }
        let baseTokens = baseline.items.flatMap {
            $0.trials.filter { $0.exit != .polluted }.compactMap(\.tokens)
        }.map { Double($0.total) }
        let tokenDelta: Double? = (withTokens.isEmpty || baseTokens.isEmpty) ? nil
            : withTokens.reduce(0, +) / Double(withTokens.count)
                - baseTokens.reduce(0, +) / Double(baseTokens.count)
        self.init(pairs: pairs, timeDeltaSeconds: timeDelta,
                  polluted: baseline.items.reduce(0) { $0 + $1.polluted },
                  tokenDeltaPerAttempt: tokenDelta)
    }

    /// The paired-difference estimator. **Moved to ``PairedDifference/summarize(_:)``** now that a second
    /// feature needs it; kept here, forwarding, so existing callers are untouched.
    public static func pairedStats(_ deltas: [Double]) -> (mean: Double, se: Double?) {
        PairedDifference.summarize(deltas)
    }
}
