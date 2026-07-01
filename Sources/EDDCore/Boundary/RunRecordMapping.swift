import Foundation

/// The pure mapping between a run's in-memory results and the **committed** run-record family
/// (`benchmark.json` / `grading.json`) that `skillet run` produces (Spec 006 producer obligation) and
/// the eval-viewer consumes. Kept in EDDCore, beside the codecs, because it is the *authoritative*
/// contract: `pass^k` must re-derive from the committed `benchmark.json` — never from the gitignored
/// `.skillet/runs` cache (constitution P2 / D3). Top-level keys (`metadata`/`runs`/`run_summary`;
/// `expectations`/`summary` with viewer-exact `text`/`passed`/`evidence`) are the frozen surface;
/// inner fields evolve additively (F8 tolerant-reader discipline).

public extension BenchmarkFile {
    /// Build the committed `benchmark.json` from a run — **viewer-faithful at the boundary, skillet-owned
    /// for pass^k**. `runs[]` is **one row per trial** (`configuration:"default"` — F7's single behavioral
    /// arm; `run_number`; that trial's `expectations[]`; and a `result` whose `passed`/`failed`/`total`/
    /// `pass_rate` count *expectations in that trial* — the meaning skill-creator's eval-viewer reads).
    /// skillet's improved pass^k lives in the additive `consistency` block (the shape real skill-creator
    /// artifacts established) and re-derives offline from `consistency.per_eval` — never from the gitignored
    /// cache (P2/D3), and never by overloading the viewer's per-run `result` semantics.
    init(report: RunReport, evals: [EvalResult], harness: String, k: Int, judge: SkilletConfig.Judge) {
        // One viewer-faithful row per trial; `result` counts are EXPECTATIONS graded in that trial.
        var runRows: [JSONValue] = []
        var allTrialRates: [Double] = []
        for eval in evals {
            for (index, trial) in eval.trials.enumerated() {
                let total = trial.verdicts.count
                let passed = trial.verdicts.filter(\.passed).count
                let rate = total == 0 ? 0 : Double(passed) / Double(total)
                allTrialRates.append(rate)
                runRows.append(.object([
                    "configuration": .string("default"),
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

        // Skillet-owned pass^k, re-derivable offline. `mean_pass_rate` averages the expectation pass-rate
        // across the eval's trials; `pass_power_k` is the eval's binary pass^k (all recorded trials passed).
        let perEval: [JSONValue] = zip(report.evals, evals).map { row, eval in
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

        self.init(fields: [
            "metadata": .object([
                "skill_name": .string(report.skill),
                "harness": .string(harness),
                "k": .number(Double(k)),
                "runs_per_configuration": .number(Double(k)),
                "evals_run": .array(report.evals.map { .string($0.id) }),
                "judge": .object(["provider": .string(judge.provider), "model": .string(judge.model)])
            ]),
            "runs": .array(runRows),
            "consistency": .object([
                "k": .number(Double(k)),
                "meaningful": .bool(report.measurable),
                "suite_pass_power_k": .number(report.passK),
                "flaky_eval_ids": .array(report.evals.filter { $0.status == .flaky }.map { .string($0.id) }),
                "per_eval": .array(perEval)
            ]),
            "run_summary": .object(["default": .object(["pass_rate": Self.stats(allTrialRates)])])
        ])
    }

    /// Viewer-shaped `{mean,stddev,min,max}` aggregate over per-trial pass rates (population stddev).
    private static func stats(_ xs: [Double]) -> JSONValue {
        guard !xs.isEmpty else { return .object(["mean": .number(0), "stddev": .number(0), "min": .number(0), "max": .number(0)]) }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        return .object(["mean": .number(mean), "stddev": .number(variance.squareRoot()), "min": .number(xs.min() ?? 0), "max": .number(xs.max() ?? 0)])
    }

    /// Re-derive per-eval `(passes, recorded)` from the committed `benchmark.json` — the authoritative
    /// `pass^k` recompute basis (P2/D3). Reads skillet's **`consistency.per_eval`** (`perfect_passes`/
    /// `runs`), not the viewer's per-run `result` (whose counts are *expectations*, a different unit).
    /// `eval_id` is coerced string-or-number so real numeric-id records aren't silently dropped.
    var evalCounts: [(id: String, passes: Int, recorded: Int)] {
        guard let perEval = fields["consistency"]?.objectValue?["per_eval"]?.arrayValue else { return [] }
        return perEval.compactMap { entry in
            guard let o = entry.objectValue,
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
    /// survives `rm -rf .skillet` (P2). The skill name comes from the record's metadata.
    init(benchmark: BenchmarkFile) {
        self.init(skill: benchmark.skillName ?? "unknown", counts: benchmark.evalCounts)
    }
}

public extension GradingFile {
    /// Build `grading.json` from a run's results: one expectation row per `(eval, criterion)`, `passed`
    /// iff that criterion held in **every** recorded trial (`pass^k`-consistent); `evidence` is a
    /// representative judge rationale (the first failing trial's, else the first trial's). Criteria are
    /// positional + identical across a trial's verdicts, indexed by the first trial that produced any.
    init(evals: [EvalResult]) {
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
            ])
        ])
    }
}
