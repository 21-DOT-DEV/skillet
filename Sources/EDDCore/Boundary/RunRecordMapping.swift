import Foundation

/// The pure mapping between a run's in-memory results and the **committed** run-record family
/// (`benchmark.json` / `grading.json`) that `skillet run` produces (Spec 006 producer obligation) and
/// the eval-viewer consumes. Kept in EDDCore, beside the codecs, because it is the *authoritative*
/// contract: `pass^k` must re-derive from the committed `benchmark.json` — never from the gitignored
/// `.skillet/runs` cache (constitution P2 / D3). Top-level keys (`metadata`/`runs`/`run_summary`;
/// `expectations`/`summary` with viewer-exact `text`/`passed`/`evidence`) are the frozen surface;
/// inner fields evolve additively (F8 tolerant-reader discipline).

/// Provenance stamped into the **committed** records (audit M3; design §7.2/§9.4, constitution II):
/// the exact judge (provider / model / prompt version) and the executor's binary version that produced
/// a result — so a cross-run delta is attributable to a harness change vs a skill change, and v1- vs
/// v2-graded runs stay distinguishable after a cache wipe. Provenance not captured at run time is
/// unrecoverable later; `"unknown"` is the defined sentinel (§7.4) when a field can't be resolved.
public struct RunProvenance: Sendable, Equatable {
    /// The grader's stable id — `text-judge` / `grounded-judge` / `replay` / `none` (F16). Recorded
    /// additively in the committed `judge` block so text vs grounded stay distinguishable in the
    /// committed record after a `.skillet/` cache wipe — not only by a coincidental `prompt_version`.
    public let judgeId: String
    public let judgeProvider: String
    public let judgeModel: String
    public let judgePromptVersion: String
    public let executorBinaryVersion: String

    public init(judgeId: String = "text-judge", judgeProvider: String, judgeModel: String, judgePromptVersion: String, executorBinaryVersion: String) {
        self.judgeId = judgeId
        self.judgeProvider = judgeProvider
        self.judgeModel = judgeModel
        self.judgePromptVersion = judgePromptVersion
        self.executorBinaryVersion = executorBinaryVersion
    }
}

public extension BenchmarkFile {
    /// Build the committed `benchmark.json` from a run — **viewer-faithful at the boundary, skillet-owned
    /// for pass^k**. `runs[]` is **one row per trial** (`configuration:"default"` — F7's single behavioral
    /// arm; `run_number`; that trial's `expectations[]`; and a `result` whose `passed`/`failed`/`total`/
    /// `pass_rate` count *expectations in that trial* — the meaning skill-creator's eval-viewer reads).
    /// skillet's improved pass^k lives in the additive `consistency` block (the shape real skill-creator
    /// artifacts established) and re-derives offline from `consistency.per_eval` — never from the gitignored
    /// cache (P2/D3), and never by overloading the viewer's per-run `result` semantics.
    init(report: RunReport, evals: [EvalResult], harness: String, k: Int, provenance: RunProvenance) throws {
        try self.init(skill: report.skill, behavioral: (report: report, evals: evals), trigger: nil,
                      harness: harness, k: k, provenance: provenance, preserving: nil)
    }

    /// The F14 master producer: either axis may run alone; the axis that did **not** run this
    /// invocation is carried over verbatim from `preserving` (the previously committed file), so a
    /// `--axis trigger` run can never destroy the behavioral record or vice versa — `benchmark.json`
    /// stays latest-run-per-axis. Trigger trials are viewer-faithful rows under
    /// `configuration: "trigger"` (the format's native discriminator; the viewer groups by it), and
    /// trigger `consistency.per_eval` entries carry an additive `"axis": "trigger"` marker so the
    /// behavioral recompute (``evalCounts``) never mixes axes.
    /// Throws when the without-skill arm names one test twice — writing a record is the moment raw
    /// results become something later runs will join on, so it is where the key's promise is made.
    init(
        skill: String,
        behavioral: (report: RunReport, evals: [EvalResult])?,
        baseline: [EvalResult]? = nil,
        trigger: [TriggerEvalResult]?,
        harness: String,
        k: Int,
        provenance: RunProvenance,
        preserving prior: BenchmarkFile?
    ) throws {
        let priorConsistency = prior?.fields["consistency"]?.objectValue
        let priorPerEval = priorConsistency?["per_eval"]?.arrayValue ?? []
        let priorSummary = prior?.fields["run_summary"]?.objectValue

        // --- Behavioral axis: fresh rows when it ran, else carried from the prior record. ---
        var behavioralRows: [JSONValue] = []
        var behavioralPerEval: [JSONValue] = []
        var behavioralConsistency: [String: JSONValue] = [:]
        var behavioralSummary: JSONValue?
        /// A block picked up from a saved file, together with the name it was found under — so what is
        /// written back cannot end up labelled as the other arm.
        var carriedBehavioral: (key: String, value: JSONValue)?
        // F15: an --ab run writes the canonical arm names (`with_skill`/`without_skill` — the
        // viewer's exact grouping strings, reserved for F15 by Specs/009); a single-arm run keeps
        // F7's `"default"`, which readers treat as the with-arm. A single-arm behavioral run
        // supersedes the whole behavioral axis, including any prior baseline (latest-run-per-axis:
        // a stale baseline paired with fresh with-arm rows would mint cross-run deltas).
        let withConfiguration = baseline != nil ? "with_skill" : "default"
        if let behavioral {
            // **The summary and the raw results must describe the same tests, in the same order.** They
            // are matched up position by position below, and pairing two lists that way silently stops at
            // the shorter one: measured, a summary describing three tests handed one result recorded a
            // single row, and the other two vanished from the committed file with nothing to show for it.
            // That is the same fault as quietly scoring fewer tests than a file lists, which this file
            // already refuses in two other places — reachable only from a caller outside this program,
            // which is exactly why the shape is checked rather than assumed.
            guard behavioral.report.evals.map(\.id) == behavioral.evals.map(\.evalId) else {
                throw EDDError.invalidArtifact(
                    path: "benchmark.json",
                    reason: "the summary of this run names different tests, or names them in a different "
                        + "order, than the results it was given",
                    fix: "build the summary from the same results being recorded — pairing them up "
                        + "position by position would drop whichever tests the shorter list does not reach")
            }
            var allTrialRates: [Double] = []
            for eval in behavioral.evals {
                for (index, trial) in eval.trials.enumerated() {
                    let total = trial.verdicts.count
                    let passed = trial.verdicts.filter(\.passed).count
                    let rate = total == 0 ? 0 : Double(passed) / Double(total)
                    // An attempt that never produced a result is not a zero-scoring attempt.
                    if trial.exit != .error { allTrialRates.append(rate) }
                    behavioralRows.append(.object([
                        "configuration": .string(withConfiguration),
                        "eval_id": .string(eval.evalId),
                        "run_number": .number(Double(index + 1)),
                        "expectations": .array(trial.verdicts.map { v in
                            .object(["text": .string(v.criterion), "passed": .bool(v.passed), "evidence": .string(v.rationale)])
                        }),
                        "result": .object([
                            "passed": .number(Double(passed)),
                            "failed": .number(Double(total - passed)),
                            "total": .number(Double(total)),
                            "pass_rate": .number(rate)
                        ])
                    ]))
                }
            }
            // `mean_pass_rate` averages the expectation pass-rate across the eval's trials;
            // `pass_power_k` is the eval's binary pass^k (all recorded trials passed).
            behavioralPerEval = zip(behavioral.report.evals, behavioral.evals).map { row, eval in
                let rates = Self.gradedAttempts(eval.trials).map(Self.criterionRate)
                // **A test that recorded no attempts states no verdict.** The counts stay, because they
                // are facts — nothing ran, nothing passed. The three figures below are conclusions drawn
                // from attempts, and drawing them from none says "measured, and it failed", which is
                // indistinguishable from a test that ran and got everything wrong. The same rule already
                // governs the without-skill rows and the block that summarises the whole run; this row
                // and the routing one were the two places it had not reached, so a file could withhold
                // its summary because nothing was measured and state a failed result underneath.
                var entry: [String: JSONValue] = [
                    "eval_id": .string(row.id),
                    "runs": .number(Double(row.recorded)),
                    "perfect_passes": .number(Double(row.passes))
                ]
                if row.recorded > 0 {
                    entry["pass_power_k"] = .number(row.status == .pass ? 1 : 0)
                    entry["flaky"] = .bool(row.status == .flaky)
                    entry["mean_pass_rate"] = .number(rates.reduce(0, +) / Double(rates.count))
                }
                return .object(entry)
            }
            behavioralConsistency = [
                "k": .number(Double(k)),
                "meaningful": .bool(behavioral.report.measurable),
                "suite_pass_power_k": .number(behavioral.report.passK),
                "suite_pass_1": .number(behavioral.report.passOne),   // additive (§14-11)
                "flaky_eval_ids": .array(behavioral.report.evals.filter { $0.status == .flaky }.map { .string($0.id) })
            ]
            let withDurations = behavioral.evals.flatMap { $0.trials.compactMap(\.durationSeconds) }
            // **The same shape whether or not there is a second arm.** A single-arm run measures wall
            // clock exactly as a two-arm run does, and used to drop it here — so a reader charting how
            // long a suite takes got the number from a comparison run and nothing from a plain one, for
            // no reason it could detect. One builder for every arm block means a field can no longer be
            // present on one and quietly missing on its sibling.
            // **Attempts that failed, ran out of time, or were never graded are all counted here, and
            // that is deliberate.** How long an attempt took, and what it cost, are true of an attempt
            // that broke down partway just as much as of one that finished — the clock ran and the tokens
            // were spent either way, which is the same reason a failed attempt's cost is recorded at all.
            //
            // **Including the never-graded ones is the point, not an oversight.** The token figure below
            // is a sum, so it is the record of what was spent, and money spent on an attempt that failed
            // to grade was still spent — leaving it out would under-report the bill, which is the failure
            // with real consequences. The standard way to express efficiency agrees: cost per successful
            // result divides everything paid by the results obtained, keeping the top of that fraction
            // whole. The *quality* figures elsewhere do exclude never-graded attempts, and that difference
            // is intended: what a run cost and what it measured are separate questions.
            //
            // What is left out is an attempt that was *disqualified*, because a run that used the skill
            // when it was supposed to be without it measured nothing, rather than measuring something
            // badly. Queried twice in review; written down so the difference reads as a decision.
            let withTokens = behavioral.evals.flatMap { $0.trials.compactMap(\.tokens) }
            behavioralSummary = Self.armSummary(passRates: allTrialRates, durations: withDurations,
                                                tokens: withTokens)
        } else {
            behavioralRows = prior?.runs.filter { $0.objectValue?["configuration"]?.stringValue != "trigger" } ?? []
            behavioralPerEval = priorPerEval.filter { $0.objectValue?["axis"]?.stringValue != "trigger" }
            for key in ["k", "meaningful", "suite_pass_power_k", "suite_pass_1", "flaky_eval_ids"] {
                if let value = priorConsistency?[key] { behavioralConsistency[key] = value }
            }
            // **Carried under the name it was found under.** Which block is picked up and which name it is
            // written back under used to be decided in two separate places, from two different rules — one
            // preferring the single-arm block, the other preferring the comparison name. A saved file
            // holding both then had its single-arm numbers written back under the comparison name: the
            // label said one thing and the figures were the other's, and the block that name belonged to
            // was dropped. Deciding both together at once makes that impossible to express rather than
            // something to keep in step. (skillet itself never writes both — a comparison run replaces the
            // whole block — so this needs a file merged or edited by hand.)
            carriedBehavioral = priorSummary?["default"].map { (key: "default", value: $0) }
                ?? priorSummary?["with_skill"].map { (key: "with_skill", value: $0) }
            behavioralSummary = carriedBehavioral?.value
        }

        // --- Baseline arm (F15): canonical `without_skill` rows; polluted trials (the §9.2
        // tripwire fired) are excluded from rows and counts — unmeasured, never a graded result.
        // Baseline artifacts are behavioral-axis members, so the non-trigger carry filters above
        // already preserve them (rows + per_eval) on a trigger-only run.
        var baselineRows: [JSONValue] = []
        var baselinePerEval: [JSONValue] = []
        var baselineSummary: JSONValue?
        var deltaSummary: JSONValue?
        if let baseline, let behavioral {
            var baselineTrialRates: [Double] = []
            for eval in baseline {
                let measured = eval.trials.filter { $0.exit != .polluted }
                for (index, trial) in measured.enumerated() {
                    let total = trial.verdicts.count
                    let passed = trial.verdicts.filter(\.passed).count
                    let rate = total == 0 ? 0 : Double(passed) / Double(total)
                    // An attempt that never produced a result is not an attempt that scored zero. The
                    // row itself is still written, because the attempt genuinely happened; only the
                    // average leaves it out. Same rule as the with-skill side above.
                    if trial.exit != .error { baselineTrialRates.append(rate) }
                    baselineRows.append(.object([
                        "configuration": .string("without_skill"),
                        "eval_id": .string(eval.evalId),
                        "run_number": .number(Double(index + 1)),
                        "expectations": .array(trial.verdicts.map { v in
                            .object(["text": .string(v.criterion), "passed": .bool(v.passed), "evidence": .string(v.rationale)])
                        }),
                        "result": .object([
                            "passed": .number(Double(passed)),
                            "failed": .number(Double(total - passed)),
                            "total": .number(Double(total)),
                            "pass_rate": .number(rate)
                        ])
                    ]))
                }
            }
            baselinePerEval = baseline.map { eval in
                // **One set of attempts decides all four numbers below.** The count came from attempts
                // that were merely not disqualified, while the scores came from attempts that were
                // actually graded — two different sets. When every attempt failed to grade, that left a
                // count above zero and no scores to average, so the row divided by nothing: the run
                // finished, the money was spent, and then writing the results file failed outright with
                // "cannot write not-a-number". Short of that, the two sets simply disagreed, and a saved
                // file that stated a different denominator from the run that produced it cannot be
                // re-checked against that run — which is the one promise this file exists to keep.
                let graded = Self.gradedAttempts(eval.trials)
                let passes = graded.filter(\.passed).count
                let status = PassK.status(passes: passes, recorded: graded.count)
                let rates = graded.map(Self.criterionRate)
                // **A test whose every attempt was thrown out states no result.** An attempt is disqualified
                // when a skill was used in the run that was meant to be without one; it is never graded.
                // When every attempt goes that way, this row used to say the test *failed* and scored
                // zero — indistinguishable from a test that ran and got everything wrong, and the most
                // flattering possible reading of the skill being tested: "without it, this did not work."
                // The counts beside it stay, because they are facts: nothing ran, nothing passed, and
                // this many attempts were thrown out. It is the two derived verdicts that are withheld.
                //
                // The block that summarises the whole run was given this rule two rounds ago and the
                // per-test rows underneath it were missed — the fifteenth time in this feature that a
                // rule has held in one place and been absent from its sibling.
                var row: [String: JSONValue] = [
                    "arm": .string("baseline"),
                    "eval_id": .string(eval.evalId),
                    "runs": .number(Double(graded.count)),
                    "perfect_passes": .number(Double(passes)),
                    "polluted": .number(Double(eval.polluted))
                ]
                if !graded.isEmpty {
                    row["pass_power_k"] = .number(status == .pass ? 1 : 0)
                    row["flaky"] = .bool(status == .flaky)
                    row["mean_pass_rate"] = .number(rates.reduce(0, +) / Double(rates.count))
                }
                return .object(row)
            }
            let baseDurations = baseline.flatMap { $0.trials.filter { $0.exit != .polluted }.compactMap(\.durationSeconds) }
            let withDurations = behavioral.evals.flatMap { $0.trials.compactMap(\.durationSeconds) }
            let baseTokens = baseline.flatMap { $0.trials.filter { $0.exit != .polluted }.compactMap(\.tokens) }
            baselineSummary = Self.armSummary(passRates: baselineTrialRates, durations: baseDurations,
                                              tokens: baseTokens)
            // **Two shapes, one per block, and the rule is worth stating because it looks like an
            // inconsistency.** Every entry in this difference block is signed text — `+0.50`, `+13.0`,
            // `+1700` — while every entry in the two per-run blocks beside it is an object of figures
            // (`mean`, `stddev`, `min`, `max`, or a set of counts). So `time_seconds` is a string here
            // and an object there, under one name. That is deliberate and uniform: a difference is a
            // single signed quantity and carries its sign in the text, whereas a run's own measurement is
            // a spread. A reader needs the rule "differences are text, runs are objects" rather than
            // per-field knowledge; nothing in this file departs from it.
            //
            // The canonical delta block: signed fixed-precision strings (predecessor
            // `Benchmark.swift` format parity — `+0.50` / `+13.0` / `+1700`); tokens zeros until
            // F60's usage telemetry. `pass_rate` uses the **paired** estimator — the SAME
            // `ABComparison` math the report carries, so `skillet.run/1`'s `ab.paired_mean_delta`
            // and the committed record can never disagree (review finding, 2026-07-07: a pooled
            // trial-mean difference diverges when pollution removes baseline trials unevenly).
            // `time_seconds` stays the pooled-mean difference, matching the per-arm stats beside it
            // and the live `timeDeltaSeconds`.
            // Both arms, not just the looked-up one: a repeat on either side pairs one result twice.
            let comparison = ABComparison(withArm: try UniqueByName(behavioral.evals, name: \.evalId),
                                          baseline: try UniqueByName(baseline, name: \.evalId))
            // Preserve the live report's optionality (review round 2): a key appears only when the
            // quantity was MEASURED — `mean([])` is not a measurement, and writing "+0.0"/"+N.0"
            // off an all-polluted arm would fabricate a delta the live report honestly withholds.
            let measuredPairs = comparison.perEval.count - comparison.unmeasuredEvalIds.count
            var delta: [String: JSONValue] = [:]
            if measuredPairs > 0 {
                delta["pass_rate"] = .string(String(format: "%+.2f", locale: Self.neutralNumbers, comparison.pairedMeanDelta))
            }
            if !withDurations.isEmpty && !baseDurations.isEmpty {
                delta["time_seconds"] = .string(String(format: "%+.1f", locale: Self.neutralNumbers, Self.mean(withDurations) - Self.mean(baseDurations)))
            }
            // **One token entry, and only the figure whose difference means something.** How much the
            // model read is stable whether or not its provider's cache happened to be warm, so a
            // difference in it is attributable to the skill. The cached-versus-fresh split is not: it
            // moves on timing luck, so publishing *its* difference under a heading that reads as "what
            // the skill did" would invite exactly the misreading this shape exists to prevent. The split
            // is in each run's own block, where warmth is a fact about that run.
            //
            // Averaged per attempt, like the elapsed-time entry beside it — a total would move with how
            // many attempts were run rather than with the skill. Present only when *both* runs counted,
            // for the same reason the elapsed-time entry is: a difference needs two measurements.
            let withTokenCounts = behavioral.evals.flatMap { $0.trials.compactMap(\.tokens) }
            let baseTokenCounts = baseline.flatMap { $0.trials.filter { $0.exit != .polluted }.compactMap(\.tokens) }
            if !withTokenCounts.isEmpty && !baseTokenCounts.isEmpty {
                let withMean = Self.mean(withTokenCounts.map { Double($0.total) })
                let baseMean = Self.mean(baseTokenCounts.map { Double($0.total) })
                // **Named for its unit, because its neighbours do not need to be and this does.** The
                // pass-rate and elapsed-time differences beside it sit next to per-run blocks that are
                // plainly per-attempt — each is a spread with a mean in it — so "the difference in
                // elapsed time" can only mean one thing. The per-run token block is a *total* across
                // every attempt, so an unqualified token difference beside it invites being read as a
                // difference of totals, which it is not: totals move with how many attempts each run
                // recorded, and the without-skill run records fewer whenever a trial is thrown out.
                // **Written with decimals, because it is an average and averages are not whole.** Rounded
                // to whole tokens, a run reporting 90.5 saved `+90` and read back as 90 — the live figure
                // and the one re-derived from the file disagreeing, which this file's own rule says they
                // must not. The average is fractional whenever the two sides recorded different numbers of
                // attempts, which is any run where one attempt was thrown out. Two places is the finest
                // precision already used in this block and is far below any difference that could matter
                // for a token count; it cannot make them agree exactly — no fixed number of digits can —
                // but it moves the disagreement below a hundredth of a token.
                //
                // The figure printed on screen stays whole: that is for a person reading a table, not for
                // a later run to re-derive from.
                delta["total_tokens_per_attempt"] = .string(String(format: "%+.2f", locale: Self.neutralNumbers, withMean - baseMean))
            }
            if !delta.isEmpty { deltaSummary = .object(delta) }
        } else if behavioral == nil {
            // Trigger-only run after an --ab run: carry the arms' summaries like every other
            // behavioral-axis artifact.
            baselineSummary = priorSummary?["without_skill"]
            deltaSummary = priorSummary?["delta"]
        }

        // --- Trigger axis (F14): deterministic single-expectation rows, `configuration: "trigger"`. ---
        var triggerRows: [JSONValue] = []
        var triggerPerEval: [JSONValue] = []
        var triggerConsistency: [String: JSONValue] = [:]
        var triggerSummary: JSONValue?
        if let trigger {
            var triggerTrialRates: [Double] = []
            for result in trigger {
                let criterion = result.shouldTrigger ? "skill triggers" : "skill does not trigger"
                for (index, trial) in result.trials.enumerated() {
                    let passed = trial.exit == .passed && trial.firedTarget == result.shouldTrigger
                    // Third place with the same fault: an attempt that never produced a result counted
                    // as one that scored zero, so the summary below stated a rate of nothing-passed for a
                    // check that was never measured — which is what its own comment says it must not do.
                    if trial.exit != .error { triggerTrialRates.append(passed ? 1 : 0) }
                    let evidence: String
                    if trial.exit == .error {
                        evidence = "trial \(trial.exit.rawValue) (not measured)"
                    } else if trial.exit == .timeout {
                        // **Its own wording, because it is graded and the other is not.** Running out of
                        // time shared the "not measured" text with an attempt that never ran, so the row
                        // said one thing was checked and failed while the words beside it said nothing was
                        // measured. Worded for both directions: a check can require that the skill is
                        // reached for, or that it is not, and running out of time fails either — not
                        // because the answer was seen to be wrong, but because it was never seen at all
                        // within the time allowed, and an unobserved answer cannot be recorded as a pass.
                        evidence = "ran out of time before this could be shown to hold"
                    } else if trial.firedTarget {
                        evidence = "fired the target skill"
                    } else if trial.firedOther.isEmpty {
                        evidence = "did not fire"
                    } else {
                        evidence = "routed to: \(trial.firedOther.joined(separator: ", "))"
                    }
                    // **An attempt that never produced a result is not a graded failure.** This row used
                    // to say one thing was checked and it failed, while its own evidence beside it read
                    // "not measured" — the object contradicted itself. Worse, the summary below already
                    // left such attempts out, so the per-attempt rows and the figures they are supposed to
                    // add up to disagreed: anything recomputing a rate from the rows got a different
                    // answer from the recompute this file exists to support.
                    //
                    // What is left out is exactly what the summary leaves out — attempts that never ran.
                    // An attempt that ran out of time did produce an answer: the skill did not fire in the
                    // time allowed. It stays a graded failure here because it is counted as one there, and
                    // the two must agree; leaving it out of both was considered and would contradict the
                    // rule, settled earlier in this work, that running out of time is a real result.
                    let graded = trial.exit != .error
                    triggerRows.append(.object([
                        "configuration": .string("trigger"),
                        "eval_id": .string(result.evalId),
                        "run_number": .number(Double(index + 1)),
                        "expectations": .array(graded ? [
                            .object(["text": .string(criterion), "passed": .bool(passed), "evidence": .string(evidence)])
                        ] : []),
                        "result": .object([
                            "passed": .number(passed ? 1 : 0),
                            "failed": .number(graded && !passed ? 1 : 0),
                            "total": .number(graded ? 1 : 0),
                            "pass_rate": .number(passed ? 1 : 0)
                        ])
                    ]))
                }
            }
            // **Graded attempts, not attempts made.** This counted every attempt, so one that never
            // produced a result was averaged in as a zero — the same defect the headline figure had, in
            // the check beside it. Building the counts from the record rather than by hand is what stops
            // the two drifting apart again.
            let axis = RunReport.Axis(counts: trigger.map(EvalCounts.init))
            triggerPerEval = zip(axis.evals, trigger).map { row, result in
                // Same rule as the two rows beside it: nothing tried, nothing concluded. This one already
                // noticed the case — it wrote a zero score for a check that never ran — and answered it
                // by inventing the figure rather than withholding it.
                var entry: [String: JSONValue] = [
                    "axis": .string("trigger"),
                    "eval_id": .string(row.id),
                    "runs": .number(Double(row.recorded)),
                    "perfect_passes": .number(Double(row.passes)),
                    "query": .string(result.query)
                ]
                if row.recorded > 0 {
                    entry["pass_power_k"] = .number(row.status == .pass ? 1 : 0)
                    entry["flaky"] = .bool(row.status == .flaky)
                    entry["mean_pass_rate"] = .number(Double(row.passes) / Double(row.recorded))
                }
                return .object(entry)
            }
            triggerConsistency = [
                "trigger_k": .number(Double(k)),
                "trigger_meaningful": .bool(axis.measurable),
                "trigger_suite_pass_power_k": .number(axis.passK),
                "trigger_suite_pass_1": .number(axis.passOne),
                "trigger_flaky_eval_ids": .array(axis.evals.filter { $0.status == .flaky }.map { .string($0.id) })
            ]
            // **The same rule as the two blocks beside it: nothing measured, nothing stated.** This wrote a
            // score of zero for a routing check that recorded no attempts at all, which reads as "we asked
            // and the skill was never reached for" — the most damning possible reading — rather than "we
            // never asked". The two other summary blocks were given this rule a round ago and this one was
            // missed, which is the twelfth time in this feature that a rule has lived in one place and been
            // absent from its sibling.
            if let rate = Self.stats(triggerTrialRates) {
                triggerSummary = .object(["pass_rate": rate])
            }
        } else {
            triggerRows = prior?.runs.filter { $0.objectValue?["configuration"]?.stringValue == "trigger" } ?? []
            triggerPerEval = priorPerEval.filter { $0.objectValue?["axis"]?.stringValue == "trigger" }
            for key in ["trigger_k", "trigger_meaningful", "trigger_suite_pass_power_k", "trigger_suite_pass_1", "trigger_flaky_eval_ids"] {
                if let value = priorConsistency?[key] { triggerConsistency[key] = value }
            }
            triggerSummary = priorSummary?["trigger"]
        }

        let newJudge = JSONValue.object([
            "id": .string(provenance.judgeId),   // additive (F16): the grader's stable id
            "provider": .string(provenance.judgeProvider),
            "model": .string(provenance.judgeModel),
            "prompt_version": .string(provenance.judgePromptVersion)
        ])
        let judgeEntry: JSONValue =
            if behavioral != nil { newJudge }
            else if let carried = prior?.metadata?["judge"] { carried }
            else { newJudge }

        var metadata: [String: JSONValue] = [
            // Always the caller's explicit name — a trigger-only first run must never commit
            // "unknown" and poison the offline recompute (review round 1, finding 2).
            "skill_name": .string(skill),
            // `harness`/`k`/`runs_per_configuration` describe the behavioral arm (the pre-trigger
            // viewer reads them), so they follow the behavioral carry rule like `evals_run` and the
            // judge block: fresh when that axis ran, carried when it didn't (round 2, finding 3).
            // The trigger axis's own k lives in `consistency.trigger_k`.
            "harness": behavioral != nil ? .string(harness) : (prior?.metadata?["harness"] ?? .string(harness)),
            "k": behavioral != nil ? .number(Double(k)) : (prior?.metadata?["k"] ?? .number(Double(k))),
            "runs_per_configuration": behavioral != nil ? .number(Double(k)) : (prior?.metadata?["runs_per_configuration"] ?? .number(Double(k))),
            // Carried from the prior record on a trigger-only run, like the behavioral rows themselves.
            "evals_run": behavioral.map { .array($0.report.evals.map { .string($0.id) }) }
                ?? prior?.metadata?["evals_run"] ?? .array([]),
            // Additive provenance (M3; §7.2): the executor stamps the latest write; the judge block
            // describes the *behavioral* verdicts, so a judge-free trigger-only run carries the prior
            // record's judge rather than overwriting it with the "none" sentinel.
            "executor_binary_version": .string(provenance.executorBinaryVersion),
            "judge": judgeEntry
        ]
        if let trigger {
            metadata["trigger_cases_run"] = .array(trigger.map { .string($0.evalId) })   // additive (F14)
        } else if let priorCases = prior?.metadata?["trigger_cases_run"] {
            metadata["trigger_cases_run"] = priorCases
        }

        var consistency = behavioralConsistency.merging(triggerConsistency) { current, _ in current }
        consistency["per_eval"] = .array(behavioralPerEval + baselinePerEval + triggerPerEval)
        var summary: [String: JSONValue] = [:]
        if let behavioralSummary {
            // Fresh --ab runs (and carried post-ab records) key the with-arm canonically; every
            // other case keeps F7's "default".
            // A freshly measured comparison names its with-arm canonically; a freshly measured single arm
            // keeps the plain name. Anything carried from a saved file keeps the name it was found under,
            // decided at the moment it was picked up so the two cannot disagree.
            let withKey = carriedBehavioral?.key ?? (baseline != nil ? "with_skill" : "default")
            summary[withKey] = behavioralSummary
        }
        if let baselineSummary { summary["without_skill"] = baselineSummary }
        if let deltaSummary { summary["delta"] = deltaSummary }
        if let triggerSummary { summary["trigger"] = triggerSummary }

        // **What this version does not recognise is kept, not thrown away.**
        //
        // This document is described as keeping anything it does not recognise, so that a field written
        // by a newer version survives being rewritten by an older one. It did the opposite: rewriting
        // built a fresh document out of only the fields it knew, and everything else vanished. Measured
        // before this changed — a field at the top and a field inside the settings block were both handed
        // in and both discarded. Building a new object out of the fields you understand is the named way
        // this data gets lost.
        //
        // The rule is the standard one for combining a new document with an existing one: sections
        // addressed by name are merged into, and lists are replaced whole. A name says what a new value
        // corresponds to; a position in a list says nothing, so the attempts recorded below are this
        // run's and replace what was there.
        //
        // Keeping rather than discarding is deliberate. Discarding only makes sense alongside a
        // description of every field that is allowed, which this format does not have — it permits fields
        // to be added — so discarding would delete legitimate ones. A figure carried forward from an
        // earlier run can at least be seen and corrected; one destroyed cannot be recovered by anyone.
        self.init(fields: Self.merging(
            [
                "metadata": .object(Self.merging(metadata, into: prior?.metadata)),
                "runs": .array(behavioralRows + baselineRows + triggerRows),
                "consistency": .object(Self.merging(consistency, into: prior?.fields["consistency"]?.objectValue)),
                "run_summary": .object(Self.merging(summary, into: prior?.fields["run_summary"]?.objectValue))
            ],
            into: prior?.fields))
    }

    /// Everything `prior` held, with `written` laid over the top — so a name this version does not know
    /// survives, and a name it does know takes the new value.
    private static func merging(_ written: [String: JSONValue],
                                into prior: [String: JSONValue]?) -> [String: JSONValue] {
        guard let prior else { return written }
        return prior.merging(written) { _, new in new }
    }

    /// **Numbers in this file are written the same way on every machine.** A figure written as `+0.50`
    /// here is read back with a plain text-to-number conversion, which only understands a dot; on a
    /// machine whose region writes `0,50` that conversion returns nothing, and a four-figure count
    /// written as `+1,100` reads back as `1` — the same measurement off by three orders of magnitude,
    /// with nothing to show for it.
    ///
    /// **Measured: this does not happen, and is named here anyway.** Forcing the machine's region to a
    /// comma-decimal one still produced `+0.50` and `+1100`, because this way of formatting applies no
    /// regional conventions unless a setting is handed to it — which is documented, not luck. It is
    /// handed one regardless, for the reason a mainstream analyser enforces as a rule: naming it makes
    /// the guarantee visible where someone reads the code. Two separate reviews of this file reported
    /// the opposite after reading the call site, which is the cost of leaving it implied.
    static let neutralNumbers = Locale(identifier: "en_US_POSIX")

    /// Viewer-shaped `{mean,stddev,min,max}` aggregate over per-trial pass rates (population stddev).
    /// **Nothing to average, nothing to say.** Handed an empty list this used to answer with four zeros,
    /// which reads exactly like four real measurements that all came out at zero — the confusion this
    /// file has already been corrected for twice. An empty list is a real state here, not a mistake: it
    /// is what a run produces when every attempt was disqualified. So it is answered rather than trapped,
    /// and the rule now lives here instead of in each caller's memory.
    private static func stats(_ xs: [Double]) -> JSONValue? {
        guard !xs.isEmpty else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        return .object(["mean": .number(mean), "stddev": .number(variance.squareRoot()), "min": .number(xs.min() ?? 0), "max": .number(xs.max() ?? 0)])
    }

    /// Canonical per-arm summary (F15): viewer-shaped stats for `pass_rate`. `time_seconds` appears only
    /// when the arm actually measured durations — zero-stats for an unmeasured arm would read as real
    /// instant trials and let the offline time delta fabricate a number (review round 2).
    ///
    /// **A quantity nothing measured has no entry here.** Token counts used to be written as zeros on
    /// every arm and a zero difference beside them, which reads as "measured, and it came to nothing"
    /// rather than "nobody counted". That was three lines below a comment saying a key appears only when
    /// the quantity was measured, and it was the only field in this file breaking that rule — elapsed
    /// time has always been left out when no attempt was timed. Absence is how this file says
    /// "not measured", in one way rather than two.
    /// **Nothing to say, so nothing is said.** This used to answer with an empty object whenever it had
    /// no figures at all — reachable when every attempt failed to be set up, since such an attempt records
    /// no score, no duration and no cost. That wrote an arm into the file whose value was `{}`, which the
    /// three rules inside this very routine exist to prevent: each of the figures below is withheld rather
    /// than invented when there is nothing behind it, and then the container holding none of them was
    /// written anyway. Answering "nothing" lets the caller leave the arm out entirely, which is what the
    /// two helpers it calls already do.
    private static func armSummary(passRates: [Double], durations: [Double],
                                   tokens: [TokenCounts] = []) -> JSONValue? {
        var arm: [String: JSONValue] = [:]
        // The helper owns the "nothing measured, nothing stated" rule now, so this reads as one thing
        // rather than a check here that has to agree with a branch there.
        // **The score follows the same rule as everything beside it, and it is the one that most needed
        // to.** A run whose every attempt was disqualified — a skill fired where none may exist, so not
        // one attempt is a usable measurement — used to record a score of zero here, indistinguishable
        // from a run that genuinely got everything wrong. That reads as the most flattering possible
        // result for the skill under test: "without it, nothing worked." The command refuses such a
        // comparison, but the file is written before the refusal and outlives it, so anything reading the
        // file later saw a fabricated zero with nothing marking it as one.
        if let rate = stats(passRates) { arm["pass_rate"] = rate }
        if let seconds = stats(durations) { arm["time_seconds"] = seconds }
        if let block = tokenBlock(tokens) { arm["tokens"] = block }
        return arm.isEmpty ? nil : .object(arm)
    }

    /// **The roll-up and its parts, never a bare `input_tokens`.** Two published conventions use that one
    /// name for opposite quantities — the input that missed the cache, and the whole input regardless of
    /// caching — so a single field under that name is read two ways and one of them is wrong by roughly
    /// the size of the cached context. Each field here is named for exactly what it holds, and
    /// `total_tokens` is the roll-up, which is the name the quantity carries in comparable tools.
    ///
    /// The parts travel alongside so a reader who wants spending rather than volume can price each kind
    /// themselves — a cached read and a fresh one cost very differently — without this tool publishing a
    /// money figure it has no prices for.
    /// Reachable from the tests on purpose: the empty case cannot be produced through the caller, which
    /// checks first, so the only way to pin what it answers is to ask it directly.
    /// **The attempts a pass rate is built from: those that produced a result.**
    ///
    /// Three separate places built this list, each by filtering the attempts slightly differently, and an
    /// attempt that was never graded slipped into all three as a zero — dragging every average down and
    /// contradicting the score computed beside them. One function so there is one answer.
    static func gradedAttempts(_ trials: [TrialResult]) -> [TrialResult] {
        trials.filter { $0.exit != .error && $0.exit != .polluted }
    }

    /// The share of a graded attempt's criteria that passed.
    static func criterionRate(_ trial: TrialResult) -> Double {
        trial.verdicts.isEmpty ? 0 : Double(trial.verdicts.filter(\.passed).count) / Double(trial.verdicts.count)
    }

    static func tokenBlock(_ counts: [TokenCounts]) -> JSONValue? {
        // **Nothing counted, nothing to say.** Reading the first of an empty list stops the program on the
        // spot, and the obvious repair — starting the sum at zero — would answer with a full set of zeros,
        // which is the invented measurement this file spent a round removing. Saying "nothing" instead
        // puts the file's own rule inside the helper rather than in the memory of whoever calls it. An
        // empty list is the ordinary state of every run made without a real model, not a mistake, so it
        // belongs in the answer rather than being ruled out by the shape of the input.
        guard let first = counts.first else { return nil }
        // **A total too large to write down is left unsaid, not rounded off.** Adding these can reach a
        // number that changes value on its way into this file, and the entry exists to state what was
        // counted — so when it cannot be stated exactly, no entry is written, exactly as when nothing was
        // counted at all. Reachable only from counts far beyond any real run.
        var total: TokenCounts? = first
        for next in counts.dropFirst() { total = total.flatMap { $0 + next } }
        guard let total else { return nil }
        // The names come from the counts themselves, so this file and the diagnostic file a run leaves
        // behind cannot end up calling the same four numbers different things.
        return .object(total.jsonObject)
    }

    private static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    /// Re-derive per-eval `(passes, recorded)` from the committed `benchmark.json` — the authoritative
    /// `pass^k` recompute basis (P2/D3). Reads skillet's **`consistency.per_eval`** (`perfect_passes`/
    /// `runs`), not the viewer's per-run `result` (whose counts are *expectations*, a different unit).
    /// `eval_id` is coerced string-or-number so real numeric-id records aren't silently dropped.
    /// Each of the three refuses the file when a count in it is not a whole number — see
    /// ``counts(where:)`` for why passing over such an entry is worse than stopping.
    var evalCounts: [EvalCounts] {
        // Behavioral WITH-arm = non-trigger and non-baseline (F15's `arm` marker keeps arms unmixed).
        get throws { try counts { $0["axis"]?.stringValue != "trigger" && $0["arm"]?.stringValue != "baseline" } }
    }

    /// The trigger axis's per-case `(passes, recorded)` — entries marked `"axis": "trigger"` (F14).
    var triggerCounts: [EvalCounts] {
        get throws { try counts { $0["axis"]?.stringValue == "trigger" } }
    }

    /// The baseline arm's per-eval `(passes, recorded)` — entries marked `"arm": "baseline"` (F15;
    /// `recorded` here is the *measured* count, polluted trials already excluded by the producer).
    var baselineCounts: [EvalCounts] {
        get throws { try counts { $0["arm"]?.stringValue == "baseline" } }
    }

    /// The committed arms' mean wall-clock delta (with − without) from `run_summary` (F15); `nil`
    /// when either arm's `time_seconds` stats are absent — the producer omits them for an arm with
    /// no measured durations, so absence means unmeasured, mirroring the live report's optionality.
    /// **The token difference the record states, read back.** Written as signed text like every other
    /// entry in that block, so it is parsed rather than taken as a number; `nil` when the record does not
    /// state one, which means one of the two sides counted nothing.
    var abTokenDelta: Double? {
        guard let text = fields["run_summary"]?.objectValue?["delta"]?
            .objectValue?["total_tokens_per_attempt"]?.stringValue else { return nil }
        return Double(text)
    }

    var abTimeDelta: Double? {
        let summary = fields["run_summary"]?.objectValue
        guard let with = summary?["with_skill"]?.objectValue?["time_seconds"]?.objectValue?["mean"]?.numberValue,
              let without = summary?["without_skill"]?.objectValue?["time_seconds"]?.objectValue?["mean"]?.numberValue
        else { return nil }
        return with - without
    }

    /// Total baseline trials the pollution tripwire disqualified, summed from the arm's `per_eval`
    /// entries (F15).
    var abPolluted: Int {
        // **Absent means none; present but unreadable refuses the file.** Most entries never carry this
        // field, so its absence is ordinary and stays ordinary. A value that is there and cannot be read
        // used to count as none, which quietly turns "attempts were thrown out" into "nothing was thrown
        // out" — the opposite of what the file says, on the number that decides whether a comparison can
        // be trusted at all. The counts beside it are already refused on the same terms.
        get throws {
            guard let perEval = fields["consistency"]?.objectValue?["per_eval"]?.arrayValue else { return 0 }
            var total = 0
            for entry in perEval {
                guard let o = entry.objectValue, o["arm"]?.stringValue == "baseline" else { continue }
                let name = o["eval_id"].flatMap(Self.coercedId) ?? "an entry"
                if let thrown = try Self.wholeCount(o["polluted"], named: "polluted", test: name) {
                    total += thrown
                }
            }
            return total
        }
    }

    /// **A count that cannot be a count refuses the file rather than removing the test.**
    ///
    /// Each entry says how many times a test ran and how many of those runs passed. Both have to be whole
    /// numbers. An entry whose count is something else — `2.5`, or a word — used to be dropped without a
    /// word, and the score was then worked out from the entries that remained: a confident figure over
    /// fewer tests than the file holds, with nothing marking it as such. Quietly shrinking what a score is
    /// computed over is the specific practice trustworthy-benchmark guidance names as untrustworthy,
    /// because it can only push the figure up.
    ///
    /// `2.0` and `2` are the same number and both are accepted — a file format has no separate whole-number
    /// type, so the test is the value, not how it was written.
    ///
    /// An entry with no count at all is still passed over, as before: that is a different question from
    /// the one settled here, and it is recorded rather than changed quietly.
    /// **The one place a score may be built from numbers rather than from a record.** These arrive from a
    /// saved file where the separation between attempts made and attempts graded was already decided when
    /// the file was written, so there is nothing left here to get wrong.
    private func counts(where include: ([String: JSONValue]) -> Bool) throws -> [EvalCounts] {
        guard let perEval = fields["consistency"]?.objectValue?["per_eval"]?.arrayValue else { return [] }
        return try perEval.compactMap { entry in
            guard let o = entry.objectValue, include(o) else { return nil }
            // **A test's name is the key every result is matched up by, so an entry without a usable one
            // cannot take part in anything.** Both shapes used to pass silently: an entry with no name at
            // all was dropped and the score computed from what remained, and a name given as `1.5` was
            // turned into the text "1.5" and used as a real test name. The counts beside it are already
            // refused when they cannot be counts; treating the more important field more leniently was
            // the inconsistency. The standard reading of a required field is that the document fails.
            guard let id = o["eval_id"].flatMap(Self.coercedId) else {
                throw EDDError.invalidArtifact(
                    path: "benchmark.json",
                    reason: o["eval_id"] == nil
                        ? "an entry has no test name"
                        : "an entry gives its test name as \(Self.describe(o["eval_id"])), which cannot name a test",
                    fix: "give every entry a name that is text or a whole number — results are matched up "
                        + "by it, so an entry without one cannot be compared against anything")
            }
            guard let passes = try Self.wholeCount(o["perfect_passes"], named: "perfect_passes", test: id),
                  let recorded = try Self.wholeCount(o["runs"], named: "runs", test: id)
            else { return nil }
            // **The two counts have to make sense together, not just on their own.** More runs passing
            // than were ever attempted describes nothing that can happen, and it used to be accepted:
            // measured, five passes out of three attempts came back reading as "this test is unreliable"
            // rather than as a file that cannot be scored. A count below none did the same, and a
            // negative attempt count reached the printed summary as "observed k=-1".
            guard passes <= recorded else {
                throw EDDError.invalidArtifact(
                    path: "benchmark.json",
                    reason: "test '\(id)' says \(passes) of its runs passed but that it ran \(recorded) times",
                    fix: "correct that entry, or delete the file and measure again — more runs cannot pass "
                        + "than were attempted, so no score drawn from it would mean anything")
            }
            return EvalCounts(id: id, passes: passes, graded: recorded)
        }
    }

    /// `nil` when the entry says nothing about this count; the whole number when it says one; and a
    /// refusal when it says something that is not one.
    private static func wholeCount(_ value: JSONValue?, named: String, test: String) throws -> Int? {
        guard let value else { return nil }
        guard let number = value.numberValue, let whole = Int(exactly: number), whole >= 0 else {
            throw EDDError.invalidArtifact(
                path: "benchmark.json",
                reason: "test '\(test)' gives \(named) as \(Self.describe(value)), "
                    + "which is not a whole number of runs, or fewer than none",
                fix: "correct that entry, or delete the file and measure again — passing over the entry "
                    + "would score this skill on fewer tests than the file lists, and say nothing about it")
        }
        return whole
    }

    /// skill-creator ids are commonly numeric; accept a JSON string or number (mirrors `EvalsFile`).
    /// Names are commonly written as plain numbers in these files, so a whole number is accepted and
    /// read as its digits. A number that is not whole is **not** a name: it used to be turned into text
    /// and used as one, so `1.5` became a test called "1.5" — looser than the counts beside it, which are
    /// already refused when they are not whole.
    private static func coercedId(_ value: JSONValue) -> String? {
        if let s = value.stringValue { return s }
        if let n = value.numberValue { return Int(exactly: n).map(String.init) }
        return nil
    }

    /// The value as it actually appears, for a message about it — a list or an object used to be reported
    /// as `0`, which describes nothing that was in the file.
    private static func describe(_ value: JSONValue?) -> String {
        guard let value else { return "nothing" }
        if let s = value.stringValue { return "'\(s)'" }
        if let n = value.numberValue { return "\(n)" }
        if value.arrayValue != nil { return "a list" }
        if value.objectValue != nil { return "an object" }
        return "something that is not text or a number"
    }
}

public extension RunReport {
    /// Re-derive the report offline from a committed `benchmark.json` — the basis for a `pass^k` that
    /// survives `rm -rf .skillet` (P2). The skill name comes from the record's metadata; the trigger
    /// axis re-derives from its own marked `per_eval` entries when present (F14), and the A/B block
    /// rebuilds from the baseline-arm entries (F15) — same paired math and units as the live path
    /// (trial full-pass rates: `perfect_passes / runs`).
    /// **Throws when the saved file names one test twice — on either side.** The second door results come
    /// in by:
    /// a file written by an older version, edited by hand, or merged from a branch. The comparison below
    /// used to build its own lookup keeping the first entry for a name and dropping the rest, so a
    /// repeated name silently paired the wrong two results — and this is the path that rebuilds a
    /// comparison months later, when nobody is watching.
    init(benchmark: BenchmarkFile) throws {
        // **Every arm, including the one that measures which skill a model reaches for.** The two arms
        // that compare with-skill against without-skill were checked and this third one was not, so a
        // saved file naming one routing check twice produced two rows for one check and a score with the
        // wrong number underneath it: measured, one check recorded once as passing and once as failing
        // came back as `0.5`, a half-success invented from a single check. The same rule was given to
        // this arm on the live path two rounds ago and its saved-file twin was missed — the thirteenth
        // time in this feature that a rule has held in one place and been absent from its sibling.
        let triggerCounts: [EvalCounts]
        do { triggerCounts = try UniqueByName(try benchmark.triggerCounts, name: \.id).items }
        catch let repeated as RepeatedName { throw repeated.asInvalidArtifact(path: "benchmark.json") }
        // **Both sides, not just the one that gets looked up.** The doc above promised the saved file was
        // checked for a repeated name; only the without-skill side was, so a repeated name on the
        // with-skill side sailed through into the score and the pairing — a wrong `pass^k` and a wrong
        // comparison, from a file nobody would think to suspect.
        let withCounts: [EvalCounts]
        do { withCounts = try UniqueByName(try benchmark.evalCounts, name: \.id).items }
        catch let repeated as RepeatedName { throw repeated.asInvalidArtifact(path: "benchmark.json") }
        let baseCounts = try benchmark.baselineCounts
        var ab: ABComparison?
        if !baseCounts.isEmpty {
            // The SHARED paired builder (measured-pair rules included) — offline and live cannot
            // diverge because there is only one implementation of the math.
            let baseById: UniqueByName<EvalCounts>
            do { baseById = try UniqueByName(baseCounts, name: \.id) }
            catch let repeated as RepeatedName { throw repeated.asInvalidArtifact(path: "benchmark.json") }
            let pairs: [ABComparison.Pair] = withCounts.map { with in
                let base = baseById[with.id]
                return (id: with.id, withPasses: with.passes, withRecorded: with.graded,
                        basePasses: base?.passes ?? 0, baseRecorded: base?.graded ?? 0)
            }
            ab = ABComparison(pairs: pairs, timeDeltaSeconds: benchmark.abTimeDelta,
                              polluted: try benchmark.abPolluted,
                              tokenDeltaPerAttempt: benchmark.abTokenDelta)
        }
        self.init(
            skill: benchmark.skillName ?? "unknown",
            counts: withCounts,
            trigger: triggerCounts.isEmpty ? nil : Axis(counts: triggerCounts),
            ab: ab
        )
    }
}

public extension GradingFile {
    /// Build `grading.json` from a run's results: one expectation row per `(eval, criterion)`, `passed`
    /// iff that criterion held in **every** recorded trial (`pass^k`-consistent); `evidence` is a
    /// representative judge rationale (the first failing trial's, else the first trial's). Criteria are
    /// positional + identical across a trial's verdicts, indexed by the first trial that produced any.
    /// Carries an additive `judge` block (M3): these verdicts are judge-produced, so which judge —
    /// provider, model, prompt version — is part of the record's meaning (re-grade provenance, §9.4).
    init(evals: [EvalResult], provenance: RunProvenance) {
        var rows: [JSONValue] = []
        for eval in evals {
            guard let template = eval.trials.first(where: { !$0.verdicts.isEmpty }) else { continue }
            for index in template.verdicts.indices {
                let perTrial = eval.trials.compactMap { $0.verdicts.indices.contains(index) ? $0.verdicts[index] : nil }
                // `pass^k`-consistent: a criterion passes only if it was judged in EVERY recorded trial
                // and passed each time. A trial that produced no verdicts (timeout/errored) must not let
                // a criterion claim "passed in every trial".
                let judgedEveryTrial = perTrial.count == eval.trials.count
                let passedAll = judgedEveryTrial && perTrial.allSatisfy(\.passed)
                let evidence: String = judgedEveryTrial
                    ? (perTrial.first(where: { !$0.passed })?.rationale ?? perTrial.first?.rationale ?? "")
                    : "not graded in \(eval.trials.count - perTrial.count) of \(eval.trials.count) trial(s) (errored or timed out)"
                rows.append(.object([
                    "eval_id": .string(eval.evalId),
                    "text": .string(template.verdicts[index].criterion),
                    "passed": .bool(passedAll),
                    "evidence": .string(evidence)
                ]))
            }
        }
        let passed = rows.filter { $0.objectValue?["passed"]?.boolValue == true }.count
        let total = rows.count
        self.init(fields: [
            "expectations": .array(rows),
            "summary": .object([
                "passed": .number(Double(passed)),
                "failed": .number(Double(total - passed)),
                "total": .number(Double(total)),
                "pass_rate": .number(total == 0 ? 0 : Double(passed) / Double(total))
            ]),
            "judge": .object([
                "id": .string(provenance.judgeId),   // additive (F16): the grader's stable id
                "provider": .string(provenance.judgeProvider),
                "model": .string(provenance.judgeModel),
                "prompt_version": .string(provenance.judgePromptVersion)
            ])
        ])
    }
}
