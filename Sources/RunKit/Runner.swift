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
    /// How to start timing an attempt. Held as "make me a stopwatch" rather than as the clock itself,
    /// because a clock kept as *some clock or other* cannot hand out a moment on demand — the kind of clock
    /// has to be captured at the one point it is still known, which is here. Defaults to the real clock
    /// that only counts forward, so nothing about a run changes; a test hands in one whose time it moves by
    /// hand, which is the only way to check that the grader's time is left out without also depending on
    /// how busy the machine is (charter 1.4.0).
    let startTiming: @Sendable () -> Stopwatch

    public init(adapter: any HarnessAdapter, judge: any Judge, workspaces: WorkspaceManager = WorkspaceManager(), evidencePolicy: EvidencePolicy = .listingOnly, clock: some Clock<Duration> = ContinuousClock()) {
        self.adapter = adapter
        self.judge = judge
        self.workspaces = workspaces
        self.evidencePolicy = evidencePolicy
        self.startTiming = { Stopwatch(clock) }
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
            let id = EvalName.resolve(id: eval.id, prompt: eval.prompt, position: index)
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
        return Outcome(report: try RunReport(skill: skill.name, results: results), evals: results)
    }

    /// The F15 baseline arm: every eval `k` times under `SkillSet.none` — nothing staged
    /// (`stageSkill: false`), the harness's own isolation switch engaged (adapter), and the §9.2
    /// **pollution tripwire** armed: a trial in which *any* skill fired is `polluted` — never
    /// judged, never a graded result. Forensics land under `base/baseline/`.
    public func runBaseline(skill: SkillRef, evals: [EvalCase], k: Int, base: URL, keepWorkspace: Bool = false) async -> [EvalResult] {
        var results: [EvalResult] = []
        for (index, eval) in evals.enumerated() {
            let id = EvalName.resolve(id: eval.id, prompt: eval.prompt, position: index)
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
            // **Recorded as never graded, which is what the old comment here already called it.** This
            // line said "couldn't stage → infra failure" while writing down that the skill had been
            // measured and had failed. So a scratch folder that could not be prepared — a missing input,
            // a permission problem, a full disk — lowered the skill's score, and in a before-and-after
            // comparison could make a working skill look broken.
            let why = "the workspace for this attempt could not be prepared"
            writeForensics(trialDir: trialDir, evalId: evalId, raw: nil, trace: nil, verdicts: [],
                           exit: .error, ungradedReason: why)
            return TrialResult(exit: .error, verdicts: [])
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
        let watch = startTiming()
        // Wall-clock of the harness execution ONLY (F15 → the canonical `time_seconds` stats):
        // stamped immediately after adapter.run returns and reused on the parse/judge error paths,
        // so grader/parser time never leaks into the arms' time Δ (review round 2). When
        // adapter.run itself threw, elapsed-at-catch IS the harness time (the failed run attempt).
        var harnessSeconds: Double?
        do {
            let produced = try await adapter.run(TaskSpec(query: prompt, files: eval.files), in: workspace, skills: injection)
            raw = produced
            harnessSeconds = watch.seconds
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
                return TrialResult(exit: .polluted, verdicts: [], durationSeconds: executionSeconds,
                                   tokens: parsed.usage, tokensUnreadable: parsed.usageState == .unreadable)
            }
            let response = parsed.turns.last(where: { $0.role == .assistant })?.text ?? ""
            // The files the run produced are handed over so they survive any cut — they are what the
            // checks are about, and a check about a file the run made must never fail because the list
            // of files was too long.
            let seen = workspaces.listing(workspace, keeping: (fileContents ?? []).map(\.path))
            let evidence = JudgeEvidence(responseText: response, trace: parsed, workspaceListing: seen.files,
                                         workspaceListingTruncated: seen.truncated, fileContents: fileContents)
            for criterion in eval.expectations {
                verdicts.append(try await judge.verdict(for: criterion, evidence: evidence))
            }
            writeForensics(trialDir: trialDir, evalId: evalId, raw: produced.raw, trace: parsed, verdicts: verdicts, exit: .passed, fileContents: fileContents)
            // What the attempt read and wrote, when the tool that ran it said so. **The failure exits below
            // carry it too, whenever it exists.** They used to carry nothing, on the reasoning that a
            // failure happens before there is a session to read — which is true of one of them and false
            // of the other: an attempt whose grading fails has already had its reply back and read, so its
            // counts are real and were being thrown away. That is money spent and not recorded, and a
            // failed attempt is exactly where spending goes unnoticed, since providers charge for what a
            // request consumed whether or not it succeeded.
            return TrialResult(exit: .passed, verdicts: verdicts, durationSeconds: executionSeconds,
                               tokens: parsed.usage, tokensUnreadable: parsed.usageState == .unreadable)
        } catch let error as ProcessError {
            // **Out of time is a result; anything else here never got graded.** A run that exceeded its
            // limit did tell you something about the skill. A program that could not be started, crashed,
            // or died some other way tells you nothing about the skill — the check never ran, which is an
            // error rather than a failure. This used to record both as the skill failing.
            let exit: TrialExit = { if case .timedOut = error { return .timeout } else { return .error } }()
            let why: String? = exit == .error ? "\(error)" : nil
            // On a pre-capture failure (harness/parse threw before the post-parse capture), snapshot the
            // live workspace now so grounded evidence still survives; `?? ` keeps an already-captured
            // set (e.g. a judge failure captured before it threw).
            writeForensics(trialDir: trialDir, evalId: evalId, raw: raw?.raw, trace: trace, verdicts: verdicts, exit: exit, fileContents: fileContents ?? captureEvidence(), ungradedReason: why)
            // `nil` here in practice — this exit is reached when the program running the model failed or
            // timed out, so there is usually no session to have counted. Written as the session's own
            // counts rather than as nothing, so that if a session *is* readable the spending is recorded
            // instead of being decided by which exit happened to be taken.
            return TrialResult(exit: exit, verdicts: [], durationSeconds: harnessSeconds ?? watch.seconds,
                               tokens: trace?.usage, tokensUnreadable: trace?.usageState == .unreadable)
        } catch {
            // **Recorded as never-graded, which is what the line below always said it was.** This comment
            // read "the trial couldn't be measured" while writing down that the skill had been measured
            // and failed — so a rate limit, a grader error or a dropped connection was reported as the
            // skill getting worse. The reason was also thrown away entirely; it is now said out loud.
            let why = (error as? EDDError)?.message ?? "\(error)"
            writeForensics(trialDir: trialDir, evalId: evalId, raw: raw?.raw, trace: trace, verdicts: verdicts, exit: .error, fileContents: fileContents ?? captureEvidence(), ungradedReason: why)
            // **This is the one that was losing real numbers.** Grading runs after the reply is back and
            // read, so a grading failure leaves a fully readable session whose counts are a true record of
            // what was spent. The file kept beside the attempt for inspection already had them; what the
            // run adds up did not, so that spending vanished from every total.
            return TrialResult(exit: .error, verdicts: [], durationSeconds: harnessSeconds ?? watch.seconds,
                               tokens: trace?.usage, tokensUnreadable: trace?.usageState == .unreadable)
        }
    }

    // MARK: - Trigger axis (F14)

    /// Run every trigger case `k` times: bare query, whole-corpus frontmatter stubs (§9.3,
    /// `.only(load: [], visible: corpus)`), fired/not-fired judged **deterministically** from
    /// `Trace.skillInvocations` — no judge, one paid call per trial. Attribution (D-3): only the
    /// *target* firing counts for `should_trigger: true`; a sibling fire on a near-miss is correct
    /// routing (recorded in `firedOther` forensics either way).
    public func runTrigger(
        target: SkillRef, corpus: [SkillRef], skillsRoot: URL,
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
                    target: target, corpus: corpus, skillsRoot: skillsRoot, triggerCase: triggerCase,
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
        target: SkillRef, corpus: [SkillRef], skillsRoot: URL,
        triggerCase: (id: String, query: String, shouldTrigger: Bool),
        trialDir: URL, keepWorkspace: Bool
    ) async -> TriggerTrialResult {
        let staging: WorkspaceManager.TriggerStaging
        do {
            staging = try workspaces.prepareTrigger(corpus: corpus, skillsRoot: skillsRoot,
                                                    base: trialDir, label: "workspace")
        } catch {
            // Same as the behaviour check above: nothing about the skill was measured, so this is not a
            // result about the skill. Both were changed together, because a rule holding on one of these
            // two and not the other is how most of the defects here were made.
            let result = TriggerTrialResult(exit: .error, firedTarget: false)
            writeTriggerForensics(trialDir: trialDir, triggerCase: triggerCase, raw: nil, trace: nil,
                                  result: result, skipped: [])
            return result
        }
        defer { if !keepWorkspace { try? workspaces.destroy(staging.workspace) } }

        // If the TARGET didn't stage, the selection menu can't contain it — running anyway would mint
        // a false "not fired" (and a false PASS for every should_trigger:false near-miss). Record an
        // infrastructure failure instead: unmeasured never counts as a pass (review round 1, finding 3).
        guard staging.staged.contains(target.name) else {
            // The comment above already calls this an infrastructure failure; it was written down as a
            // measured one.
            let result = TriggerTrialResult(exit: .error, firedTarget: false)
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
            // The same rule as the behaviour check above. Both were changed together on purpose: a rule
            // that holds in one of these and not the other is how most of the defects here were made.
            let exit: TrialExit = { if case .timedOut = error { return .timeout } else { return .error } }()
            let result = TriggerTrialResult(exit: exit, firedTarget: false)
            writeTriggerForensics(trialDir: trialDir, triggerCase: triggerCase, raw: raw?.raw,
                                  trace: nil, result: result, skipped: staging.skipped)
            return result
        } catch {
            let result = TriggerTrialResult(exit: .error, firedTarget: false)
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
    /// **How long something took, measured on a clock that cannot go backwards.**
    ///
    /// Elapsed time was worked out by subtracting two readings of the wall clock — the one that says what
    /// time of day it is. That clock is adjusted: a time-sync correction, a daylight-saving change,
    /// somebody setting it by hand. An adjustment landing mid-measurement stretches, shrinks, or reverses
    /// the answer, and this project publishes the difference between how long a run takes with a skill and
    /// without it, so a distorted reading is a distorted result rather than a cosmetic wobble. A backwards
    /// adjustment could also record a duration below zero, which nothing here refuses — the sibling
    /// measurement, the count of tokens, was given exactly that refusal earlier.
    ///
    /// The clock used here only ever counts forward and keeps counting while the machine sleeps, which is
    /// what "how long did this take" means for a run someone is waiting on. The standing advice is that a
    /// wall-clock reading used to *measure* an interval rather than to *record a moment* should be this
    /// instead. It is slower to read than the alternatives by a wide margin, which does not matter: it is
    /// read twice per attempt, around work that takes seconds.
    /// Started at a moment on a given clock; tells you how much of that clock's time has passed since.
    struct Stopwatch: Sendable {
        private let span: @Sendable () -> Duration
        init(_ clock: some Clock<Duration>) {
            let start = clock.now
            self.span = { start.duration(to: clock.now) }
        }
        /// How much time has passed, in seconds.
        var seconds: Double { Runner.seconds(of: span()) }
    }

    /// A span of time as a number of seconds. Kept separate from the reading of the clock above so the
    /// arithmetic can be checked against spans of known length. With the two joined together the only way
    /// to exercise it was to wait and then bound the answer — and a ceiling on a measured wait is really a
    /// claim about how busy the machine is, which is what made the check that used to do this fail on a
    /// loaded build machine and turn the shared branch red.
    static func seconds(of elapsed: Duration) -> Double {
        Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }

    private func writeForensics(trialDir: URL, evalId: String, raw: String?, trace: Trace?, verdicts: [Verdict], exit: TrialExit, fileContents: [FileContent]? = nil, ungradedReason: String? = nil) {
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
        if let data = try? encoder.encode(TrialMeta(evalId: evalId, exit: exit, verdicts: verdicts.count,
                                                    ungradedReason: ungradedReason)) {
            try? data.write(to: trialDir.appendingPathComponent("metadata.json"), options: .atomic)
        }
    }

    /// **`ungradedReason` is why nothing was graded, and it exists because that used to be discarded.**
    /// The failure paths caught the error without even binding it, so a run could turn a rate limit into a
    /// recorded skill failure and leave nothing anywhere saying what had happened. Written beside the
    /// attempt it belongs to, which is where someone looks when a number seems wrong. Absent on every
    /// attempt that was graded, so an ordinary record is unchanged.
    private struct TrialMeta: Codable {
        let evalId: String; let exit: TrialExit; let verdicts: Int
        var ungradedReason: String?
    }
}
