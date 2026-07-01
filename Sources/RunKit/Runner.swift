import Foundation
import EDDCore
import TraceKit
import HarnessKit
import JudgeKit

/// The neutral run loop (F7): for each eval, run `k` trials through the harness adapter in a fresh
/// sandbox, judge each expectation against the trial's evidence, classify the exit, and aggregate to a
/// pure ``RunReport``. Orchestration only — every effect is an injected seam (adapter, judge,
/// workspace), so the whole loop is provable end-to-end with the `ReplayAdapter` + `ReplayJudge`, with
/// no live harness or model.
///
/// Per trial it also writes the gitignored `.skillet/runs` forensics (`raw.jsonl`, `trace.json`,
/// `verdicts.json`, `metadata.json`) — the replay source + per-trial record. That cache is **deletable**
/// (constitution P2/D3): the authoritative `pass^k` re-derives from the committed `benchmark.json`, so
/// the bulky sandbox is torn down after each trial unless `keepWorkspace` is set.
public struct Runner {
    let adapter: any HarnessAdapter
    let judge: any Judge
    let workspaces: WorkspaceManager

    public init(adapter: any HarnessAdapter, judge: any Judge, workspaces: WorkspaceManager = WorkspaceManager()) {
        self.adapter = adapter
        self.judge = judge
        self.workspaces = workspaces
    }

    /// A completed run: the pure report plus per-eval trial detail. The command builds + writes the
    /// committed `benchmark.json` / `grading.json` from these via EDDCore's record mapping.
    public struct Outcome: Sendable {
        public let report: RunReport
        public let evals: [EvalResult]
    }

    /// Run every eval `k` times under `base` (the `.skillet/runs/<ts>` cache root).
    public func run(skill: SkillRef, evals: [EvalCase], k: Int, injection: SkillSet, base: URL, keepWorkspace: Bool = false) async throws -> Outcome {
        var results: [EvalResult] = []
        for (index, eval) in evals.enumerated() {
            let id = eval.id ?? "eval-\(index)"
            guard let prompt = eval.prompt else {
                results.append(EvalResult(evalId: id, trials: []))   // no prompt → can't run → FAILs (0 passes)
                continue
            }
            var trials: [TrialResult] = []
            for trial in 0..<max(k, 0) {
                // Cache path uses the **index**, never the eval id — a hostile id (`../escape`) must not
                // path-traverse out of `.skillet/runs`. The real id stays in records + forensics.
                let trialDir = base.appendingPathComponent("eval-\(index)/trial-\(trial)", isDirectory: true)
                trials.append(await runTrial(skill: skill, eval: eval, evalId: id, prompt: prompt, injection: injection,
                                             trialDir: trialDir, keepWorkspace: keepWorkspace))
            }
            results.append(EvalResult(evalId: id, trials: trials))
        }
        return Outcome(report: RunReport(skill: skill.name, results: results), evals: results)
    }

    /// One trial: prepare sandbox → run → parse → judge each criterion → classify exit → record
    /// forensics → tear down the sandbox (unless `keepWorkspace`).
    private func runTrial(skill: SkillRef, eval: EvalCase, evalId: String, prompt: String, injection: SkillSet, trialDir: URL, keepWorkspace: Bool) async -> TrialResult {
        let workspace: Workspace
        do {
            workspace = try workspaces.prepare(skill: skill, files: eval.files, base: trialDir, label: "workspace")
        } catch {
            writeForensics(trialDir: trialDir, evalId: evalId, raw: nil, trace: nil, verdicts: [], exit: .failed)   // couldn't stage → infra failure
            return TrialResult(exit: .failed, verdicts: [])
        }
        defer { if !keepWorkspace { try? workspaces.destroy(workspace) } }

        // Hoisted so the catch paths persist whatever was gathered before a parse/judge failure — the raw
        // harness output + any partial verdicts are most useful exactly when a trial errors (the cache is
        // the debugging/replay record). A failed trial still reports `verdicts: []` for pass^k.
        var raw: RawTrace?
        var trace: Trace?
        var verdicts: [Verdict] = []
        do {
            let produced = try await adapter.run(TaskSpec(query: prompt, files: eval.files), in: workspace, skills: injection)
            raw = produced
            let parsed = try adapter.parseTrace(produced)
            trace = parsed
            let response = parsed.turns.last(where: { $0.role == .assistant })?.text ?? ""
            let listing = (try? workspaces.listing(workspace)) ?? []
            let evidence = JudgeEvidence(responseText: response, trace: parsed, workspaceListing: listing)
            for criterion in eval.expectations {
                verdicts.append(try await judge.verdict(for: criterion, evidence: evidence))
            }
            writeForensics(trialDir: trialDir, evalId: evalId, raw: produced.raw, trace: parsed, verdicts: verdicts, exit: .passed)
            return TrialResult(exit: .passed, verdicts: verdicts)
        } catch let error as ProcessError {
            let exit: TrialExit = { if case .timedOut = error { return .timeout } else { return .failed } }()
            writeForensics(trialDir: trialDir, evalId: evalId, raw: raw?.raw, trace: trace, verdicts: verdicts, exit: exit)
            return TrialResult(exit: exit, verdicts: [])
        } catch {
            // HarnessError.executionFailed / parse / judge failure → the trial couldn't be measured, but
            // persist the raw output + partial verdicts collected so far for debugging/replay.
            writeForensics(trialDir: trialDir, evalId: evalId, raw: raw?.raw, trace: trace, verdicts: verdicts, exit: .failed)
            return TrialResult(exit: .failed, verdicts: [])
        }
    }

    /// The per-trial forensics record under `.skillet/runs` (deletable cache; best-effort I/O).
    private func writeForensics(trialDir: URL, evalId: String, raw: String?, trace: Trace?, verdicts: [Verdict], exit: TrialExit) {
        let fm = FileManager.default
        try? fm.createDirectory(at: trialDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let raw { try? Data(raw.utf8).write(to: trialDir.appendingPathComponent("raw.jsonl")) }
        if let trace, let json = try? SkilletJSON.encode(trace) {
            try? Data(json.utf8).write(to: trialDir.appendingPathComponent("trace.json"))
        }
        if !verdicts.isEmpty, let data = try? encoder.encode(verdicts) {
            try? data.write(to: trialDir.appendingPathComponent("verdicts.json"))
        }
        if let data = try? encoder.encode(TrialMeta(evalId: evalId, exit: exit, verdicts: verdicts.count)) {
            try? data.write(to: trialDir.appendingPathComponent("metadata.json"))
        }
    }

    private struct TrialMeta: Codable { let evalId: String; let exit: TrialExit; let verdicts: Int }
}
