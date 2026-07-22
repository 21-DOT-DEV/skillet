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
    /// Whether each trial captures produced-file contents for the judge (F16). `.listingOnly` (default)
    /// is the text-judge path — no content read, no cost; `.withContents` is set for the grounded judge.
    let evidencePolicy: EvidencePolicy

    public init(adapter: any HarnessAdapter, judge: any Judge, workspaces: WorkspaceManager = WorkspaceManager(), evidencePolicy: EvidencePolicy = .listingOnly) {
        self.adapter = adapter
        self.judge = judge
        self.workspaces = workspaces
        self.evidencePolicy = evidencePolicy
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

    /// The F15 baseline arm: every eval `k` times under `SkillSet.none` — nothing staged
    /// (`stageSkill: false`), the harness's own isolation switch engaged (adapter), and the §9.2
    /// **pollution tripwire** armed: a trial in which *any* skill fired is `polluted` — never
    /// judged, never a graded result. Forensics land under `base/baseline/`.
    public func runBaseline(skill: SkillRef, evals: [EvalCase], k: Int, base: URL, keepWorkspace: Bool = false) async -> [EvalResult] {
        var results: [EvalResult] = []
        for (index, eval) in evals.enumerated() {
            let id = eval.id ?? "eval-\(index)"
            guard let prompt = eval.prompt else {
                results.append(EvalResult(evalId: id, trials: []))   // no prompt → can't run → FAILs (0 passes)
                continue
            }
            var trials: [TrialResult] = []
            for trial in 0..<max(k, 0) {
                // Index-based cache path (hostile-id defense, same rule as the with-arm loop).
                let trialDir = base.appendingPathComponent("baseline/eval-\(index)/trial-\(trial)", isDirectory: true)
                trials.append(await runTrial(skill: skill, eval: eval, evalId: id, prompt: prompt, injection: SkillSet.none,
                                             trialDir: trialDir, keepWorkspace: keepWorkspace,
                                             stageSkill: false, pollutionTripwire: true))
            }
            results.append(EvalResult(evalId: id, trials: trials))
        }
        return results
    }

    /// One trial: prepare sandbox → run → parse → judge each criterion → classify exit → record
    /// forensics → tear down the sandbox (unless `keepWorkspace`). `stageSkill: false` +
    /// `pollutionTripwire: true` is the baseline-arm shape (F15).
    private func runTrial(skill: SkillRef, eval: EvalCase, evalId: String, prompt: String, injection: SkillSet, trialDir: URL, keepWorkspace: Bool, stageSkill: Bool = true, pollutionTripwire: Bool = false) async -> TrialResult {
        let workspace: Workspace
        do {
            workspace = try workspaces.prepare(skill: skill, files: eval.files, base: trialDir, label: "workspace", stageSkill: stageSkill)
        } catch {
            writeForensics(trialDir: trialDir, evalId: evalId, raw: nil, trace: nil, verdicts: [], exit: .failed)   // couldn't stage → infra failure
            return TrialResult(exit: .failed, verdicts: [])
        }
        defer { if !keepWorkspace { try? workspaces.destroy(workspace) } }
        // F16: hash the staged inputs BEFORE the run, so post-run we can capture only what the skill
        // *produced or changed* (created + modified), not leftover inputs — the snapshot-diff (D-6).
        // Only under the grounded policy; the text path skips this entirely (no cost).
        let stagedBaseline: [String: StagedSnapshot] = { if case .withContents = evidencePolicy { return workspaces.snapshotStaged(workspace) } else { return [:] } }()
        // Capture the produced/changed contents under the grounded policy — a pure filesystem snapshot
        // diff (no trace needed), so it works on failure paths too; `nil` under the text policy. An
        // **empty** produced set is itself evidence (a "wrote file X" criterion that wrote nothing), so
        // it is captured as `[]`, not skipped.
        func captureEvidence() -> [FileContent]? {
            guard case let .withContents(perFileCap, totalCap) = evidencePolicy else { return nil }
            return workspaces.readProducedContents(workspace, baseline: stagedBaseline, perFileCap: perFileCap, totalCap: totalCap)
        }

        // Hoisted so the catch paths persist whatever was gathered before a parse/judge failure — the raw
        // harness output + any partial verdicts are most useful exactly when a trial errors (the cache is
        // the debugging/replay record). A failed trial still reports `verdicts: []` for pass^k.
        var raw: RawTrace?
        var trace: Trace?
        var verdicts: [Verdict] = []
        var fileContents: [FileContent]?   // F16: hoisted so it is persisted for replay/re-grade on every exit path
        let started = Date()
        // Wall-clock of the harness execution ONLY (F15 → the canonical `time_seconds` stats):
        // stamped immediately after adapter.run returns and reused on the parse/judge error paths,
        // so grader/parser time never leaks into the arms' time Δ (review round 2). When
        // adapter.run itself threw, elapsed-at-catch IS the harness time (the failed run attempt).
        var harnessSeconds: Double?
        do {
            let produced = try await adapter.run(TaskSpec(query: prompt, files: eval.files), in: workspace, skills: injection)
            raw = produced
            harnessSeconds = Date().timeIntervalSince(started)
            let executionSeconds = harnessSeconds
            let parsed = try adapter.parseTrace(produced)
            trace = parsed
            // F16: capture produced/changed contents once here (post-parse, workspace still live) so
            // EVERY exit below persists the grounded evidence — the pollution return, a judge failure,
            // and success alike.
            fileContents = captureEvidence()
            // The §9.2 pollution tripwire (F15): on a baseline trial, ANY skill invocation means the
            // isolation claim failed on this machine/run — the trial is unmeasurable, never judged
            // (no spend on an ungradeable trial), and the report surfaces it loudly.
            if pollutionTripwire && !parsed.skillInvocations.isEmpty {
                writeForensics(trialDir: trialDir, evalId: evalId, raw: produced.raw, trace: parsed, verdicts: [], exit: .polluted, fileContents: fileContents)
                return TrialResult(exit: .polluted, verdicts: [], durationSeconds: executionSeconds)
            }
            let response = parsed.turns.last(where: { $0.role == .assistant })?.text ?? ""
            let listing = (try? workspaces.listing(workspace)) ?? []
            let evidence = JudgeEvidence(responseText: response, trace: parsed, workspaceListing: listing, fileContents: fileContents)
            for criterion in eval.expectations {
                verdicts.append(try await judge.verdict(for: criterion, evidence: evidence))
            }
            writeForensics(trialDir: trialDir, evalId: evalId, raw: produced.raw, trace: parsed, verdicts: verdicts, exit: .passed, fileContents: fileContents)
            return TrialResult(exit: .passed, verdicts: verdicts, durationSeconds: executionSeconds)
        } catch let error as ProcessError {
            let exit: TrialExit = { if case .timedOut = error { return .timeout } else { return .failed } }()
            // On a pre-capture failure (harness/parse threw before the post-parse capture), snapshot the
            // live workspace now so grounded evidence still survives; `?? ` keeps an already-captured
            // set (e.g. a judge failure captured before it threw).
            writeForensics(trialDir: trialDir, evalId: evalId, raw: raw?.raw, trace: trace, verdicts: verdicts, exit: exit, fileContents: fileContents ?? captureEvidence())
            return TrialResult(exit: exit, verdicts: [], durationSeconds: harnessSeconds ?? Date().timeIntervalSince(started))
        } catch {
            // HarnessError.executionFailed / parse / judge failure → the trial couldn't be measured, but
            // persist the raw output + partial verdicts (+ the produced-file evidence) collected so far.
            writeForensics(trialDir: trialDir, evalId: evalId, raw: raw?.raw, trace: trace, verdicts: verdicts, exit: .failed, fileContents: fileContents ?? captureEvidence())
            return TrialResult(exit: .failed, verdicts: [], durationSeconds: harnessSeconds ?? Date().timeIntervalSince(started))
        }
    }

    // MARK: - Trigger axis (F14)

    /// Run every trigger case `k` times: bare query, whole-corpus frontmatter stubs (§9.3,
    /// `.only(load: [], visible: corpus)`), fired/not-fired judged **deterministically** from
    /// `Trace.skillInvocations` — no judge, one paid call per trial. Attribution (D-3): only the
    /// *target* firing counts for `should_trigger: true`; a sibling fire on a near-miss is correct
    /// routing (recorded in `firedOther` forensics either way).
    public func runTrigger(
        target: SkillRef, corpus: [SkillRef],
        cases: [(id: String, query: String, shouldTrigger: Bool)],
        k: Int, base: URL, keepWorkspace: Bool = false
    ) async -> [TriggerEvalResult] {
        var results: [TriggerEvalResult] = []
        for (index, triggerCase) in cases.enumerated() {
            var trials: [TriggerTrialResult] = []
            for trial in 0..<max(k, 0) {
                // Index-based cache path (hostile-id defense, same rule as the behavioral loop).
                let trialDir = base.appendingPathComponent("trigger-\(index)/trial-\(trial)", isDirectory: true)
                trials.append(await runTriggerTrial(
                    target: target, corpus: corpus, triggerCase: triggerCase,
                    trialDir: trialDir, keepWorkspace: keepWorkspace
                ))
            }
            results.append(TriggerEvalResult(
                evalId: triggerCase.id, query: triggerCase.query,
                shouldTrigger: triggerCase.shouldTrigger, trials: trials
            ))
        }
        return results
    }

    private func runTriggerTrial(
        target: SkillRef, corpus: [SkillRef],
        triggerCase: (id: String, query: String, shouldTrigger: Bool),
        trialDir: URL, keepWorkspace: Bool
    ) async -> TriggerTrialResult {
        let staging: WorkspaceManager.TriggerStaging
        do {
            staging = try workspaces.prepareTrigger(corpus: corpus, base: trialDir, label: "workspace")
        } catch {
            writeTriggerForensics(trialDir: trialDir, triggerCase: triggerCase, raw: nil, trace: nil,
                                  result: TriggerTrialResult(exit: .failed, firedTarget: false), skipped: [])
            return TriggerTrialResult(exit: .failed, firedTarget: false)
        }
        defer { if !keepWorkspace { try? workspaces.destroy(staging.workspace) } }

        // If the TARGET didn't stage, the selection menu can't contain it — running anyway would mint
        // a false "not fired" (and a false PASS for every should_trigger:false near-miss). Record an
        // infrastructure failure instead: unmeasured never counts as a pass (review round 1, finding 3).
        guard staging.staged.contains(target.name) else {
            let result = TriggerTrialResult(exit: .failed, firedTarget: false)
            writeTriggerForensics(trialDir: trialDir, triggerCase: triggerCase, raw: nil, trace: nil,
                                  result: result, skipped: staging.skipped)
            return result
        }

        var raw: RawTrace?
        do {
            let visible = corpus.filter { staging.staged.contains($0.name) }
            let produced = try await adapter.run(
                TaskSpec(query: triggerCase.query),
                in: staging.workspace,
                skills: .only(load: [], visible: visible)
            )
            raw = produced
            let trace = try adapter.parseTrace(produced)
            let fired = Set(trace.skillInvocations.map(\.skill))
            let result = TriggerTrialResult(
                exit: .passed,
                firedTarget: fired.contains(target.name),
                firedOther: fired.subtracting([target.name]).sorted()
            )
            writeTriggerForensics(trialDir: trialDir, triggerCase: triggerCase, raw: produced.raw,
                                  trace: trace, result: result, skipped: staging.skipped)
            return result
        } catch let error as ProcessError {
            let exit: TrialExit = { if case .timedOut = error { return .timeout } else { return .failed } }()
            let result = TriggerTrialResult(exit: exit, firedTarget: false)
            writeTriggerForensics(trialDir: trialDir, triggerCase: triggerCase, raw: raw?.raw,
                                  trace: nil, result: result, skipped: staging.skipped)
            return result
        } catch {
            let result = TriggerTrialResult(exit: .failed, firedTarget: false)
            writeTriggerForensics(trialDir: trialDir, triggerCase: triggerCase, raw: raw?.raw,
                                  trace: nil, result: result, skipped: staging.skipped)
            return result
        }
    }

    private func writeTriggerForensics(
        trialDir: URL, triggerCase: (id: String, query: String, shouldTrigger: Bool),
        raw: String?, trace: Trace?, result: TriggerTrialResult, skipped: [String]
    ) {
        let fm = FileManager.default
        try? fm.createDirectory(at: trialDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let raw { try? Data(raw.utf8).write(to: trialDir.appendingPathComponent("raw.jsonl"), options: .atomic) }
        if let trace, let json = try? SkilletJSON.encode(trace) {
            try? Data(json.utf8).write(to: trialDir.appendingPathComponent("trace.json"), options: .atomic)
        }
        if let data = try? encoder.encode(TriggerMeta(
            evalId: triggerCase.id, query: triggerCase.query, shouldTrigger: triggerCase.shouldTrigger,
            exit: result.exit, firedTarget: result.firedTarget, firedOther: result.firedOther,
            skippedStubs: skipped
        )) {
            try? data.write(to: trialDir.appendingPathComponent("trigger.json"), options: .atomic)
        }
    }

    private struct TriggerMeta: Codable {
        let evalId: String; let query: String; let shouldTrigger: Bool
        let exit: TrialExit; let firedTarget: Bool; let firedOther: [String]; let skippedStubs: [String]
    }

    /// The per-trial forensics record under `.skillet/runs` (deletable cache; best-effort I/O).
    /// `fileContents` (F16, grounded policy) is persisted as `file_contents.json` so the exact evidence
    /// the grounded judge saw is auditable and re-gradable (F19/F25) after the workspace is destroyed —
    /// making the plan's "captured contents ride along for --record/re-grade" real.
    /// Writes are **atomic** (T4: temp + rename — a planted destination entry is *replaced*, never opened,
    /// mirroring the record writes' S6 fix). Path-injection is otherwise already precluded: the cache root
    /// is `<timestamp>-<random-uuid>` (unguessable, so a hostile repo can't pre-plant an entry) and its
    /// `.skillet/runs` prefix is symlink-verified up front by `assertCacheNotSymlinked`.
    private func writeForensics(trialDir: URL, evalId: String, raw: String?, trace: Trace?, verdicts: [Verdict], exit: TrialExit, fileContents: [FileContent]? = nil) {
        let fm = FileManager.default
        try? fm.createDirectory(at: trialDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let raw { try? Data(raw.utf8).write(to: trialDir.appendingPathComponent("raw.jsonl"), options: .atomic) }
        if let trace, let json = try? SkilletJSON.encode(trace) {
            try? Data(json.utf8).write(to: trialDir.appendingPathComponent("trace.json"), options: .atomic)
        }
        if !verdicts.isEmpty, let data = try? encoder.encode(verdicts) {
            try? data.write(to: trialDir.appendingPathComponent("verdicts.json"), options: .atomic)
        }
        // Write whenever contents were captured (grounded policy), **including an empty `[]`** — an
        // empty produced set is meaningful evidence and must be distinguishable from "not captured"
        // (text policy / old cache) after teardown. `nil` (text policy) writes nothing.
        if let fileContents, let data = try? encoder.encode(fileContents) {
            try? data.write(to: trialDir.appendingPathComponent("file_contents.json"), options: .atomic)
        }
        if let data = try? encoder.encode(TrialMeta(evalId: evalId, exit: exit, verdicts: verdicts.count)) {
            try? data.write(to: trialDir.appendingPathComponent("metadata.json"), options: .atomic)
        }
    }

    private struct TrialMeta: Codable { let evalId: String; let exit: TrialExit; let verdicts: Int }
}
