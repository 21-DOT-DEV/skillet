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
    init(report: RunReport, evals: [EvalResult], harness: String, k: Int, provenance: RunProvenance) {
        self.init(skill: report.skill, behavioral: (report: report, evals: evals), trigger: nil,
                  harness: harness, k: k, provenance: provenance, preserving: nil)
    }

    /// The F14 master producer: either axis may run alone; the axis that did **not** run this
    /// invocation is carried over verbatim from `preserving` (the previously committed file), so a
    /// `--axis trigger` run can never destroy the behavioral record or vice versa — `benchmark.json`
    /// stays latest-run-per-axis. Trigger trials are viewer-faithful rows under
    /// `configuration: "trigger"` (the format's native discriminator; the viewer groups by it), and
    /// trigger `consistency.per_eval` entries carry an additive `"axis": "trigger"` marker so the
    /// behavioral recompute (``evalCounts``) never mixes axes.
    init(
        skill: String,
        behavioral: (report: RunReport, evals: [EvalResult])?,
        baseline: [EvalResult]? = nil,
        trigger: [TriggerEvalResult]?,
        harness: String,
        k: Int,
        provenance: RunProvenance,
        preserving prior: BenchmarkFile?
    ) {
        let priorConsistency = prior?.fields["consistency"]?.objectValue
        let priorPerEval = priorConsistency?["per_eval"]?.arrayValue ?? []
        let priorSummary = prior?.fields["run_summary"]?.objectValue

        // --- Behavioral axis: fresh rows when it ran, else carried from the prior record. ---
        var behavioralRows: [JSONValue] = []
        var behavioralPerEval: [JSONValue] = []
        var behavioralConsistency: [String: JSONValue] = [:]
        var behavioralSummary: JSONValue?
        // F15: an --ab run writes the canonical arm names (`with_skill`/`without_skill` — the
        // viewer's exact grouping strings, reserved for F15 by Specs/009); a single-arm run keeps
        // F7's `"default"`, which readers treat as the with-arm. A single-arm behavioral run
        // supersedes the whole behavioral axis, including any prior baseline (latest-run-per-axis:
        // a stale baseline paired with fresh with-arm rows would mint cross-run deltas).
        let withConfiguration = baseline != nil ? "with_skill" : "default"
        if let behavioral {
            var allTrialRates: [Double] = []
            for eval in behavioral.evals {
                for (index, trial) in eval.trials.enumerated() {
                    let total = trial.verdicts.count
                    let passed = trial.verdicts.filter(\.passed).count
                    let rate = total == 0 ? 0 : Double(passed) / Double(total)
                    allTrialRates.append(rate)
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
                let rates = eval.trials.map { trial -> Double in
                    let total = trial.verdicts.count
                    return total == 0 ? 0 : Double(trial.verdicts.filter(\.passed).count) / Double(total)
                }
                let meanRate = rates.isEmpty ? 0 : rates.reduce(0, +) / Double(rates.count)
                return .object([
                    "eval_id": .string(row.id),
                    "runs": .number(Double(row.recorded)),
                    "perfect_passes": .number(Double(row.passes)),
                    "pass_power_k": .number(row.status == .pass ? 1 : 0),
                    "flaky": .bool(row.status == .flaky),
                    "mean_pass_rate": .number(meanRate)
                ])
            }
            behavioralConsistency = [
                "k": .number(Double(k)),
                "meaningful": .bool(behavioral.report.measurable),
                "suite_pass_power_k": .number(behavioral.report.passK),
                "suite_pass_1": .number(behavioral.report.passOne),   // additive (§14-11)
                "flaky_eval_ids": .array(behavioral.report.evals.filter { $0.status == .flaky }.map { .string($0.id) })
            ]
            let withDurations = behavioral.evals.flatMap { $0.trials.compactMap(\.durationSeconds) }
            behavioralSummary = baseline != nil
                ? Self.armSummary(passRates: allTrialRates, durations: withDurations)
                : .object(["pass_rate": Self.stats(allTrialRates)])
        } else {
            behavioralRows = prior?.runs.filter { $0.objectValue?["configuration"]?.stringValue != "trigger" } ?? []
            behavioralPerEval = priorPerEval.filter { $0.objectValue?["axis"]?.stringValue != "trigger" }
            for key in ["k", "meaningful", "suite_pass_power_k", "suite_pass_1", "flaky_eval_ids"] {
                if let value = priorConsistency?[key] { behavioralConsistency[key] = value }
            }
            behavioralSummary = priorSummary?["default"] ?? priorSummary?["with_skill"]
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
                    baselineTrialRates.append(rate)
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
                let measured = eval.trials.filter { $0.exit != .polluted }
                let passes = measured.filter(\.passed).count
                let status = PassK.status(passes: passes, recorded: measured.count)
                let rates = measured.map { trial -> Double in
                    let total = trial.verdicts.count
                    return total == 0 ? 0 : Double(trial.verdicts.filter(\.passed).count) / Double(total)
                }
                return .object([
                    "arm": .string("baseline"),
                    "eval_id": .string(eval.evalId),
                    "runs": .number(Double(measured.count)),
                    "perfect_passes": .number(Double(passes)),
                    "pass_power_k": .number(status == .pass ? 1 : 0),
                    "flaky": .bool(status == .flaky),
                    "mean_pass_rate": .number(rates.isEmpty ? 0 : rates.reduce(0, +) / Double(rates.count)),
                    "polluted": .number(Double(eval.polluted))
                ])
            }
            let baseDurations = baseline.flatMap { $0.trials.filter { $0.exit != .polluted }.compactMap(\.durationSeconds) }
            let withDurations = behavioral.evals.flatMap { $0.trials.compactMap(\.durationSeconds) }
            baselineSummary = Self.armSummary(passRates: baselineTrialRates, durations: baseDurations)
            // The canonical delta block: signed fixed-precision strings (predecessor
            // `Benchmark.swift` format parity — `+0.50` / `+13.0` / `+1700`); tokens zeros until
            // F60's usage telemetry. `pass_rate` uses the **paired** estimator — the SAME
            // `ABComparison` math the report carries, so `skillet.run/1`'s `ab.paired_mean_delta`
            // and the committed record can never disagree (review finding, 2026-07-07: a pooled
            // trial-mean difference diverges when pollution removes baseline trials unevenly).
            // `time_seconds` stays the pooled-mean difference, matching the per-arm stats beside it
            // and the live `timeDeltaSeconds`.
            let comparison = ABComparison(withArm: behavioral.evals, baseline: baseline)
            // Preserve the live report's optionality (review round 2): a key appears only when the
            // quantity was MEASURED — `mean([])` is not a measurement, and writing "+0.0"/"+N.0"
            // off an all-polluted arm would fabricate a delta the live report honestly withholds.
            let measuredPairs = comparison.perEval.count - comparison.unmeasuredEvalIds.count
            var delta: [String: JSONValue] = [:]
            if measuredPairs > 0 {
                delta["pass_rate"] = .string(String(format: "%+.2f", comparison.pairedMeanDelta))
            }
            if !withDurations.isEmpty && !baseDurations.isEmpty {
                delta["time_seconds"] = .string(String(format: "%+.1f", Self.mean(withDurations) - Self.mean(baseDurations)))
            }
            if !delta.isEmpty {
                delta["tokens"] = .string("+0")
                deltaSummary = .object(delta)
            }
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
                    triggerTrialRates.append(passed ? 1 : 0)
                    let evidence: String
                    if trial.exit != .passed {
                        evidence = "trial \(trial.exit.rawValue) (not measured)"
                    } else if trial.firedTarget {
                        evidence = "fired the target skill"
                    } else if trial.firedOther.isEmpty {
                        evidence = "did not fire"
                    } else {
                        evidence = "routed to: \(trial.firedOther.joined(separator: ", "))"
                    }
                    triggerRows.append(.object([
                        "configuration": .string("trigger"),
                        "eval_id": .string(result.evalId),
                        "run_number": .number(Double(index + 1)),
                        "expectations": .array([
                            .object(["text": .string(criterion), "passed": .bool(passed), "evidence": .string(evidence)])
                        ]),
                        "result": .object([
                            "passed": .number(passed ? 1 : 0),
                            "failed": .number(passed ? 0 : 1),
                            "total": .number(1),
                            "pass_rate": .number(passed ? 1 : 0)
                        ])
                    ]))
                }
            }
            let axis = RunReport.Axis(counts: trigger.map { (id: $0.evalId, passes: $0.passes, recorded: $0.recorded) })
            triggerPerEval = zip(axis.evals, trigger).map { row, result in
                .object([
                    "axis": .string("trigger"),
                    "eval_id": .string(row.id),
                    "runs": .number(Double(row.recorded)),
                    "perfect_passes": .number(Double(row.passes)),
                    "pass_power_k": .number(row.status == .pass ? 1 : 0),
                    "flaky": .bool(row.status == .flaky),
                    "mean_pass_rate": .number(row.recorded == 0 ? 0 : Double(row.passes) / Double(row.recorded)),
                    "query": .string(result.query)
                ])
            }
            triggerConsistency = [
                "trigger_k": .number(Double(k)),
                "trigger_meaningful": .bool(axis.measurable),
                "trigger_suite_pass_power_k": .number(axis.passK),
                "trigger_suite_pass_1": .number(axis.passOne),
                "trigger_flaky_eval_ids": .array(axis.evals.filter { $0.status == .flaky }.map { .string($0.id) })
            ]
            triggerSummary = .object(["pass_rate": Self.stats(triggerTrialRates)])
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
            let withKey = (baseline != nil) || (behavioral == nil && priorSummary?["with_skill"] != nil)
                ? "with_skill" : "default"
            summary[withKey] = behavioralSummary
        }
        if let baselineSummary { summary["without_skill"] = baselineSummary }
        if let deltaSummary { summary["delta"] = deltaSummary }
        if let triggerSummary { summary["trigger"] = triggerSummary }

        self.init(fields: [
            "metadata": .object(metadata),
            "runs": .array(behavioralRows + baselineRows + triggerRows),
            "consistency": .object(consistency),
            "run_summary": .object(summary)
        ])
    }

    /// Viewer-shaped `{mean,stddev,min,max}` aggregate over per-trial pass rates (population stddev).
    private static func stats(_ xs: [Double]) -> JSONValue {
        guard !xs.isEmpty else { return .object(["mean": .number(0), "stddev": .number(0), "min": .number(0), "max": .number(0)]) }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        return .object(["mean": .number(mean), "stddev": .number(variance.squareRoot()), "min": .number(xs.min() ?? 0), "max": .number(xs.max() ?? 0)])
    }

    /// Canonical per-arm summary (F15): viewer-shaped stats for `pass_rate` (+ `tokens`, zeros
    /// until F60's usage telemetry — a documented sentinel). `time_seconds` appears only when the
    /// arm actually measured durations — zero-stats for an unmeasured arm would read as real
    /// instant trials and let the offline time delta fabricate a number (review round 2).
    private static func armSummary(passRates: [Double], durations: [Double]) -> JSONValue {
        var arm: [String: JSONValue] = [
            "pass_rate": stats(passRates),
            "tokens": stats([])
        ]
        if !durations.isEmpty { arm["time_seconds"] = stats(durations) }
        return .object(arm)
    }

    private static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    /// Re-derive per-eval `(passes, recorded)` from the committed `benchmark.json` — the authoritative
    /// `pass^k` recompute basis (P2/D3). Reads skillet's **`consistency.per_eval`** (`perfect_passes`/
    /// `runs`), not the viewer's per-run `result` (whose counts are *expectations*, a different unit).
    /// `eval_id` is coerced string-or-number so real numeric-id records aren't silently dropped.
    var evalCounts: [(id: String, passes: Int, recorded: Int)] {
        // Behavioral WITH-arm = non-trigger and non-baseline (F15's `arm` marker keeps arms unmixed).
        counts { $0["axis"]?.stringValue != "trigger" && $0["arm"]?.stringValue != "baseline" }
    }

    /// The trigger axis's per-case `(passes, recorded)` — entries marked `"axis": "trigger"` (F14).
    var triggerCounts: [(id: String, passes: Int, recorded: Int)] {
        counts { $0["axis"]?.stringValue == "trigger" }
    }

    /// The baseline arm's per-eval `(passes, recorded)` — entries marked `"arm": "baseline"` (F15;
    /// `recorded` here is the *measured* count, polluted trials already excluded by the producer).
    var baselineCounts: [(id: String, passes: Int, recorded: Int)] {
        counts { $0["arm"]?.stringValue == "baseline" }
    }

    /// The committed arms' mean wall-clock delta (with − without) from `run_summary` (F15); `nil`
    /// when either arm's `time_seconds` stats are absent — the producer omits them for an arm with
    /// no measured durations, so absence means unmeasured, mirroring the live report's optionality.
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
        guard let perEval = fields["consistency"]?.objectValue?["per_eval"]?.arrayValue else { return 0 }
        return perEval.reduce(0) { total, entry in
            guard let o = entry.objectValue, o["arm"]?.stringValue == "baseline",
                  let p = o["polluted"]?.numberValue.flatMap({ Int(exactly: $0) }) else { return total }
            return total + p
        }
    }

    private func counts(where include: ([String: JSONValue]) -> Bool) -> [(id: String, passes: Int, recorded: Int)] {
        guard let perEval = fields["consistency"]?.objectValue?["per_eval"]?.arrayValue else { return [] }
        return perEval.compactMap { entry in
            guard let o = entry.objectValue, include(o),
                  let id = o["eval_id"].flatMap(Self.coercedId),
                  let passes = o["perfect_passes"]?.numberValue.flatMap({ Int(exactly: $0) }),
                  let recorded = o["runs"]?.numberValue.flatMap({ Int(exactly: $0) })
            else { return nil }
            return (id: id, passes: passes, recorded: recorded)
        }
    }

    /// skill-creator ids are commonly numeric; accept a JSON string or number (mirrors `EvalsFile`).
    private static func coercedId(_ value: JSONValue) -> String? {
        if let s = value.stringValue { return s }
        if let n = value.numberValue { return Int(exactly: n).map(String.init) ?? String(n) }
        return nil
    }
}

public extension RunReport {
    /// Re-derive the report offline from a committed `benchmark.json` — the basis for a `pass^k` that
    /// survives `rm -rf .skillet` (P2). The skill name comes from the record's metadata; the trigger
    /// axis re-derives from its own marked `per_eval` entries when present (F14), and the A/B block
    /// rebuilds from the baseline-arm entries (F15) — same paired math and units as the live path
    /// (trial full-pass rates: `perfect_passes / runs`).
    init(benchmark: BenchmarkFile) {
        let triggerCounts = benchmark.triggerCounts
        let withCounts = benchmark.evalCounts
        let baseCounts = benchmark.baselineCounts
        var ab: ABComparison?
        if !baseCounts.isEmpty {
            // The SHARED paired builder (measured-pair rules included) — offline and live cannot
            // diverge because there is only one implementation of the math.
            let baseById = Dictionary(baseCounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let pairs: [ABComparison.Pair] = withCounts.map { with in
                let base = baseById[with.id]
                return (id: with.id, withPasses: with.passes, withRecorded: with.recorded,
                        basePasses: base?.passes ?? 0, baseRecorded: base?.recorded ?? 0)
            }
            ab = ABComparison(pairs: pairs, timeDeltaSeconds: benchmark.abTimeDelta, polluted: benchmark.abPolluted)
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
