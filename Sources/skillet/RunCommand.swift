import ArgumentParser
import Foundation
import EDDCore
import ProjectKit
import ConfigYAML
import HarnessKit
import JudgeKit
import RunKit
import RenderKit

/// `skillet run` — the paid measurement command (design §6.1): run a skill's evals `k` times through
/// the harness, judge each expectation, and report aggregate `pass^k`. Estimates the trial count up
/// front and gates spend (design P9); probes the harness before spending; writes the committed
/// `benchmark.json` + `grading.json` (from which `pass^k` re-derives) plus a deletable `.skillet/runs`
/// cache. Exit codes (§5.4): 0 all PASS · 1 any non-PASS (FAIL or FLAKY) · 2 usage/no-evals · 3 harness
/// probe (missing/auth/banned) · 4 corrupt `evals.json`.
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a skill's evals and report pass^k.",
        discussion: """
        Two axes, each run where its file exists (or pick one with --axis). BEHAVIOR: each eval in \
        evaluations/evals.json runs k times in a fresh sandbox and a judge grades every expectation \
        against the run's response + post-run files. TRIGGER: each evaluations/trigger-eval.json \
        query runs k times against frontmatter-only stubs of every repo skill, judged fired/not-fired \
        deterministically from the trace — no judge call. Both print PASS/FAIL/FLAKY tables with \
        aggregate pass^k, reported separately. --ab doubles every behavioral eval with a provably \
        skill-free BASELINE arm (skills disabled at the session level, verified from each trial's \
        trace) and reports the paired per-eval Δ — "is the skill earning its tokens?". Estimates \
        trials and model calls first; won't spend above runs.confirm_above_trials without --yes; \
        --dry-run previews the plan. Writes evaluations/benchmark.json (both axes, merged per axis; \
        --ab adds canonical with_skill/without_skill rows) and grading.json (with-skill behavioral \
        runs only — trigger trials produce no judge verdicts). Commit these; pass^k re-derives from them.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "The skill to run; defaults to the only skill when exactly one is discovered.")
    var skill: String?

    /// The measurement axes (design §6.1): behavioral evals, trigger cases, or both.
    enum RunAxis: String, ExpressibleByArgument {
        case behavior, trigger, all
    }

    @Option(name: .long, help: "Axis to run: behavior, trigger, or all (default: all — each where its file exists).")
    var axis: RunAxis = .all

    @Option(name: .long, help: "Trials per eval; overrides runs.k from skillet.yaml.")
    var runs: Int?

    @Flag(name: [.customShort("n"), .long], help: "Preview the plan + trial estimate and exit without spending.")
    var dryRun = false

    @Flag(name: .long, help: "Proceed past the spend confirmation without prompting.")
    var yes = false

    @Flag(name: .customLong("no-input"), help: "Never prompt; fail if spend confirmation is required (CI).")
    var noInput = false

    @Flag(name: .customLong("keep-workspace"), help: "Keep each per-trial sandbox for debugging.")
    var keepWorkspace = false

    @Flag(name: .long, help: "Add a provably skill-free baseline arm to every behavioral eval and report the paired Δ.")
    var ab = false

    // Hidden test-only offline wiring (ReplayAdapter + ReplayJudge); the public --record/--replay is F19.
    @Flag(name: .long, help: ArgumentHelp("Test-only offline replay wiring.", visibility: .private))
    var replay = false
    @Option(name: .customLong("replay-map"), help: ArgumentHelp("Test-only replay verdict map (criterion→bool JSON).", visibility: .private))
    var replayMap: String?
    @Option(name: .customLong("replay-baseline-map"), help: ArgumentHelp("Test-only baseline-arm replay verdict map (criterion→bool JSON).", visibility: .private))
    var replayBaselineMap: String?

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
            guard let root = context.root.map({ URL(fileURLWithPath: $0) }) else {
                throw EDDError.projectNotFound(cwd: context.cwd)
            }

            let config = try loadConfig(options: options, context: context)
            let runsCfg = config?.runs ?? .init()
            let judgeCfg = config?.judge ?? .init()
            let skillsRoot = config?.project?.skillsRoot ?? "skills"
            let k = runs ?? runsCfg.k
            guard k >= 1 else {
                throw EDDError.usage(message: "--runs must be at least 1 (got \(k))", remedy: "pass --runs with a value ≥ 1, or omit it to use runs.k")
            }
            guard runsCfg.maxOutputBytes > 0 else {
                throw EDDError.usage(message: "runs.max_output_bytes must be positive (got \(runsCfg.maxOutputBytes))", remedy: "set a positive byte count in skillet.yaml, or omit it for the 64 MiB default")
            }

            let discovered = SkillScanner().scan(skillsRoot: root.appendingPathComponent(skillsRoot))
            let skillDir = try resolveSkill(discovered, requested: skill)
            let skillName = skillDir.lastPathComponent
            // The skill dir + evaluations/ are read (evals) and written (records); confine them so a
            // symlinked component can't redirect reads/writes outside the repo (P1).
            try assertNoSymlinkEscape(skillDir: skillDir, projectRoot: root, skillName: skillName)

            // Decode each axis's cases (F14 — §6.1 default: every axis whose file exists). Explicitly
            // requesting an axis makes its file required; `all` skips an absent one with a note.
            // Behavioral: absent/empty → usage (2) when required; present-but-corrupt → artifact (4).
            let cases = axis == .trigger
                ? nil
                : try loadEvals(skillDir: skillDir, skillName: skillName, required: axis == .behavior)
            let triggerCases = axis == .behavior
                ? nil
                : try loadTriggerCases(skillDir: skillDir, skillName: skillName, required: axis == .trigger)
            guard cases != nil || triggerCases != nil else {
                throw EDDError.usage(
                    message: "nothing to run for \(skillName): no usable evals.json or trigger-eval.json (absent or empty)",
                    remedy: "add cases to evaluations/evals.json and/or evaluations/trigger-eval.json (`skillet init` scaffolds both)"
                )
            }
            if let cases {
                // Fail loud on a missing/out-of-skill/symlinked fixture or bundle symlink before spending.
                try preflight(cases, skillDir: skillDir, skillName: skillName)
            }
            if triggerCases != nil {
                // The trigger axis stages a frontmatter-only stub of the target — verify the fence
                // extracts BEFORE any spend, or every trial would be an unmeasured staging failure.
                let markdown = (try? String(contentsOf: skillDir.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
                guard WorkspaceManager.frontmatterStub(markdown: markdown) != nil else {
                    throw EDDError.invalidArtifact(
                        path: "\(skillName)/SKILL.md",
                        reason: "no frontmatter fence — the trigger axis stages a frontmatter-only stub, so SKILL.md must open with a `---` block"
                    )
                }
            }
            // Free-before-paid (constitution V): refuse a lint-error skill before any dry-run/spend/probe.
            // Axis-aware: the has-evals rule only gates runs that execute behavioral evals (F14 review).
            try runLintPreflight(skillDir: skillDir, lintConfig: config?.lint ?? .init(), renderer: renderer,
                                 behavioralAxisRuns: cases != nil)

            // F15 scope (D-4): the baseline arm is behavioral-only — activation is tested with the
            // skill present (universal practice); a run executing no behavioral evals makes --ab
            // meaningless, so refuse before anything is spent ("check early and bail").
            if ab && cases == nil {
                throw EDDError.usage(
                    message: "--ab adds a without-skill baseline to behavioral evals, but no behavioral evals are running"
                        + (triggerCases != nil ? " (only the trigger axis is)" : ""),
                    remedy: "add cases to evaluations/evals.json, or drop --ab (activation is tested with the skill present)"
                )
            }
            if ab && triggerCases != nil {
                Console.emit(Rendering(stderr: "note: --ab applies to the behavior axis; the trigger axis runs single-arm\n"))
            }

            // Skipped-axis notes (Specs/009 A4): the default mode says which axis it skipped and why,
            // on stderr so machine-readable stdout stays untouched (P7).
            if axis == .all {
                if cases == nil {
                    Console.emit(Rendering(stderr: "note: no usable evals.json (absent or empty) — behavioral axis skipped (add eval cases to run it)\n"))
                }
                if triggerCases == nil {
                    Console.emit(Rendering(stderr: "note: no usable trigger-eval.json — trigger axis skipped (add {query, should_trigger} cases to run it)\n"))
                }
            }

            // Spend gate (design P9): the gate is TRIAL-denominated — `confirm_above_trials` has
            // meant trials since it shipped, so its unit never silently changes (decided in-session,
            // F14 review round 2). The CALL estimate (behavioral × 2: task + judge; trigger × 1: no
            // judge) is shown in previews and the prompt so the cost is visible before consent.
            let withArmTrials = (cases?.count ?? 0) * k
            let baselineTrials = ab ? withArmTrials : 0
            let behavioralTrials = withArmTrials + baselineTrials
            let triggerTrials = (triggerCases?.count ?? 0) * k
            let trials = behavioralTrials + triggerTrials
            // Baseline trials are judged too (same rubric, both arms — F15 A1): × 2 calls each.
            let estimatedCalls = behavioralTrials * 2 + triggerTrials
            if dryRun {
                let plan = RunPlan(
                    skill: skillName, evals: cases?.count ?? 0, k: k, trials: trials,
                    confirmAboveTrials: runsCfg.confirmAboveTrials,
                    requiresConfirmation: trials > runsCfg.confirmAboveTrials, willSpend: !replay,
                    triggerCases: triggerCases?.count, triggerTrials: triggerCases.map { _ in triggerTrials },
                    estimatedCalls: estimatedCalls,
                    abBaselineTrials: ab ? baselineTrials : nil
                )
                if options.json {
                    Console.emit(Rendering(stdout: try SkilletJSON.encode(plan) + "\n"))
                } else {
                    var parts: [String] = []
                    if let cases { parts.append("\(cases.count) eval(s) × k=\(k)\(ab ? " × 2 arms" : "")") }
                    if let triggerCases { parts.append("\(triggerCases.count) trigger case(s) × k=\(k)") }
                    Console.emit(Rendering(stdout: "plan: \(parts.joined(separator: " + ")) = \(trials) trial(s) ≈ \(estimatedCalls) model call(s) for \(skillName) (nothing spent)\n"))
                }
                return
            }
            try confirmSpend(trials: trials, estimatedCalls: estimatedCalls, limit: runsCfg.confirmAboveTrials, skill: skillName)

            // Assemble the harness + judge; probe before spending so a missing/banned binary fails fast (3).
            let timeout = DurationString.parse(runsCfg.timeout) ?? .seconds(600)
            // Trigger-only runs are judge-free (deterministic grading): no judge is built and
            // `judge.model`'s required-explicit rule (§14-4) doesn't apply — nothing gets judged.
            let backend = try buildAdapterAndJudge(
                config: config, judge: judgeCfg, timeout: timeout,
                outputLimitBytes: runsCfg.maxOutputBytes, needsJudge: cases != nil
            )
            // Strict for the paid path (refuse banned/unauth before spend); replay's probe is canned and
            // free — probed anyway so the executor's version is stamped into the records (M3 provenance).
            let harnessInfo = try await backend.adapter.probe(strict: !replay)
            // F15 D-1: prove the harness can hold a skill-free baseline BEFORE any paid trial — a
            // $0 interrogation of the resolved binary. Flag support shifts across harness versions
            // (the denylist class), so it is checked every run, never assumed; refusal is exit 3.
            if ab {
                do {
                    try await backend.adapter.verifyBaselineIsolation()
                } catch let error as EDDError {
                    throw error
                } catch {
                    throw EDDError.baselineNotIsolable(
                        harness: backend.adapter.id.rawValue,
                        reason: "the \(backend.adapter.id.rawValue) adapter does not implement baseline isolation"
                    )
                }
            }

            let skillRef = SkillRef(name: skillName, path: skillDir.path)
            try assertCacheNotSymlinked(projectRoot: root)   // confine cache writes to the repo (no symlink escape)
            try ensureCacheGitignore(projectRoot: root)   // keep the cache gitignored even without prior `init`
            // Second-resolution timestamp + a short uuid so two runs in the same second never share a path.
            let stamp = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
            let base = root.appendingPathComponent(".skillet/runs/\(stamp)", isDirectory: true)
            let runner = Runner(adapter: backend.adapter, judge: backend.judge)
            let behavioralOutcome: Runner.Outcome? = if let cases {
                try await runner.run(
                    skill: skillRef, evals: cases, k: k,
                    injection: .only(load: [skillRef]), base: base, keepWorkspace: keepWorkspace
                )
            } else { nil }
            // The baseline arm (F15): same evals, same judge + rubric (A1 — that IS the
            // comparison), `SkillSet.none` — nothing staged, isolation switch on, tripwire armed.
            let baselineResults: [EvalResult]? = if ab, let cases {
                await Runner(adapter: backend.adapter, judge: backend.baselineJudge)
                    .runBaseline(skill: skillRef, evals: cases, k: k, base: base, keepWorkspace: keepWorkspace)
            } else { nil }
            // The trigger axis (F14, §9.3): bare queries against whole-corpus frontmatter stubs,
            // fired/not-fired judged deterministically from skillInvocations — one call per trial.
            let triggerResults: [TriggerEvalResult]? = if let triggerCases {
                await runner.runTrigger(
                    target: skillRef,
                    corpus: discovered.map { SkillRef(name: $0.lastPathComponent, path: $0.path) },
                    cases: triggerCases, k: k, base: base, keepWorkspace: keepWorkspace
                )
            } else { nil }

            let report = RunReport(
                skill: skillName,
                results: behavioralOutcome?.evals ?? [],
                trigger: triggerResults,
                baseline: baselineResults
            )
            // Stamp the ACTUAL judge backend + executor version in records (not configured values) —
            // P3 review fix + M3 provenance: re-grade and harness-vs-skill attribution need the truth.
            let provenance = RunProvenance(
                judgeProvider: backend.provider, judgeModel: backend.model,
                judgePromptVersion: backend.promptVersion,
                executorBinaryVersion: harnessInfo.version.isEmpty ? "unknown" : harnessInfo.version
            )
            try writeRecords(report: report, behavioral: behavioralOutcome, baseline: baselineResults,
                             trigger: triggerResults,
                             skillDir: skillDir, harness: backend.adapter.id.rawValue, k: k,
                             provenance: provenance, base: base)

            Console.emit(try renderer.renderRun(report, nextSteps: Self.nextSteps(wroteGrading: behavioralOutcome != nil)))
            // pass^k demands all k trials pass — on every axis that ran (exit 1 on any non-PASS).
            let behavioralFailed = report.evals.count > report.passed
            let triggerFailed = report.trigger.map { $0.passed < $0.evals.count } ?? false
            if behavioralFailed || triggerFailed {
                throw SilentExit(code: ExitCode.measuredFailure.rawValue)
            }
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }

    // MARK: - assembly

    /// Resolve the skill to run by **name** (F4 idiom): the named one, the sole discovered one, or a
    /// usage error listing the choices.
    private func resolveSkill(_ discovered: [URL], requested: String?) throws -> URL {
        let available = discovered.map(\.lastPathComponent).sorted()
        if let requested {
            let byName = Dictionary(discovered.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
            guard let match = byName[requested] else {
                throw EDDError.usage(
                    message: "unknown skill: \(requested)",
                    remedy: available.isEmpty ? "no skills found under skills_root" : "choose one of: \(available.joined(separator: ", "))"
                )
            }
            return match
        }
        switch discovered.count {
        case 0: throw EDDError.usage(message: "no skills found to run", remedy: "run from a skills repository, or initialize one with `skillet init`")
        case 1: return discovered[0]
        default: throw EDDError.usage(message: "multiple skills found; name the one to run", remedy: "choose one of: \(available.joined(separator: ", "))")
        }
    }

    /// Behavioral cases. `required: false` (the `--axis all` default) skips an absent file with `nil`
    /// — "each axis where its file exists" (§6.1); everything else keeps its strict error class.
    private func loadEvals(skillDir: URL, skillName: String, required: Bool = true) throws -> [EvalCase]? {
        let raw = try SkillReader().read(skillDirectory: skillDir)
        guard let data = raw.evalsJSON else {
            guard required else { return nil }
            throw EDDError.usage(message: "no evals to run for \(skillName)", remedy: "add evaluations/evals.json (see `skillet init`)")
        }
        let evalsFile: EvalsFile
        do { evalsFile = try JSONDecoder().decode(EvalsFile.self, from: data) }
        catch { throw EDDError.invalidArtifact(path: "\(skillName)/evaluations/evals.json", reason: "not valid evals.json") }
        let cases = evalsFile.cases
        guard !cases.isEmpty else {
            // Present-but-empty skips the axis under the default mode — symmetric with the trigger
            // side's empty handling, and what an init-scaffolded skeleton contains (round 5, P1).
            guard required else { return nil }
            throw EDDError.usage(message: "no evals to run for \(skillName)", remedy: "add at least one eval to evaluations/evals.json")
        }
        // An eval with no expectations can't measure behavior — reject it rather than letting a
        // verdict-less trial pass vacuously.
        for (index, eval) in cases.enumerated() where eval.expectations.isEmpty {
            throw EDDError.invalidArtifact(
                path: "\(skillName)/evaluations/evals.json",
                reason: "eval '\(eval.id ?? "#\(index)")' has no expectations to grade"
            )
        }
        return cases
    }

    /// Trigger cases (F14) from the frozen `trigger-eval.json` (F8 codec). Same class discipline as
    /// the behavioral loader: absent → `nil` under `--axis all`, usage error when explicitly
    /// requested; present-but-corrupt → artifact (4); a case missing `query`/`should_trigger` is an
    /// artifact error, not a silent skip. Ids are positional (`trigger-<i>`) — the file's cases are
    /// bare `{query, should_trigger}` pairs.
    private func loadTriggerCases(skillDir: URL, skillName: String, required: Bool) throws -> [(id: String, query: String, shouldTrigger: Bool)]? {
        // The SHARED checker (TriggerEvalSupport) — the same judgment doctor uses to predict this
        // command, so the two can't drift (F14 review round 3). This wrapper only maps its states
        // onto run's error classes.
        switch loadTriggerEvals(skillDir: skillDir) {
        case .absent:
            guard required else { return nil }
            throw EDDError.usage(
                message: "no trigger evals for \(skillName)",
                remedy: "add evaluations/trigger-eval.json ({query, should_trigger} pairs), or run --axis behavior"
            )
        case .empty:
            guard required else { return nil }
            throw EDDError.usage(
                message: "trigger-eval.json has no cases for \(skillName)",
                remedy: "add at least one {query, should_trigger} pair, or run --axis behavior"
            )
        case .invalid(let reason):
            // Present-but-unusable is a strict artifact error under every axis mode — never a skip.
            throw EDDError.invalidArtifact(path: "\(skillName)/evaluations/trigger-eval.json", reason: reason)
        case .usable(let cases):
            return cases
        }
    }

    /// The harness adapter + judge, plus the **actual** judge `provider`/`model`/`promptVersion` for
    /// record stamping. Production: `claude-code` adapter + a `claude`-CLI-backed text judge (binary
    /// resolved once, shared by both). Tests: the offline replay wiring. An unsupported `judge.provider`
    /// fails fast rather than silently running claude-code while records claim otherwise (P3 review fix).
    /// `judge.model` is **required-explicit** (§14-4, decided): a paid run refuses (exit 2) when it's
    /// absent rather than silently picking one — the reproducibility hazard the surveyed tools carry.
    /// The replay path is exempt: no real judge is built there (canned verdicts, nothing spent).
    private func buildAdapterAndJudge(
        config: SkilletConfig?, judge judgeCfg: SkilletConfig.Judge, timeout: Duration, outputLimitBytes: Int, needsJudge: Bool = true
    ) throws -> (adapter: any HarnessAdapter, judge: any Judge, baselineJudge: any Judge, provider: String, model: String, promptVersion: String) {
        if replay {
            // Arm-distinct canned verdicts (F15 A5): the baseline map defaults to fail-all, so a
            // replayed --ab shows a deterministic positive Δ; tests override either arm's map.
            return (ReplayAdapter(),
                    ReplayJudge(loadReplayMap(), defaultPass: replayMap == nil),
                    ReplayJudge(loadBaselineReplayMap(), defaultPass: false),
                    "replay", "replay", "replay")
        }
        // Trigger-only (F14): grading is deterministic — no judge is constructed or configured-for.
        // The sentinel provenance ("none") stamps records honestly; the behavioral judge block in a
        // preserved benchmark.json is carried, not overwritten, by the axis merge.
        if !needsJudge {
            let claudePath = config?.harness?.claudeCode?.path
            let adapter = ClaudeCodeAdapter(configPath: claudePath, timeout: timeout, outputLimitBytes: outputLimitBytes)
            return (adapter, UnjudgedAxisJudge(), UnjudgedAxisJudge(), "none", "none", "none")
        }
        guard judgeCfg.provider == "claude-code" else {
            throw EDDError.usage(
                message: "judge.provider '\(judgeCfg.provider)' is not supported in Phase 1",
                remedy: "set judge.provider: claude-code in skillet.yaml (the only implemented provider)"
            )
        }
        guard let model = judgeCfg.model?.trimmingCharacters(in: .whitespaces), !model.isEmpty else {
            throw EDDError.usage(
                message: "judge.model is not set — a paid run needs an explicit judge model so verdicts are reproducible across machines",
                remedy: "add `model: <judge model>` under `judge:` in skillet.yaml (`skillet init` writes one)"
            )
        }
        let claudePath = config?.harness?.claudeCode?.path
        guard let resolved = BinaryResolver().resolve(flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: claudePath, pathName: "claude") else {
            throw EDDError.harnessNotFound(harness: "claude-code")
        }
        let adapter = ClaudeCodeAdapter(configPath: claudePath, timeout: timeout, outputLimitBytes: outputLimitBytes)
        let judge = TextJudge(runner: ClaudeCLIJudgeRunner(binaryPath: resolved.path), model: model)
        // Live --ab: the SAME judge grades both arms (F15 A1) — the comparison is the arms, never
        // the grader.
        return (adapter, judge, judge, "claude-code", model, TextJudge.promptVersion)
    }

    /// Validate that every declared eval fixture (`files[]`, resolved against the skill directory)
    /// exists, before any spend — a missing fixture is a clear artifact error, not a silent skip.
    /// Confine the skill's own I/O paths: the skill dir + `evaluations/` are read (evals) and written
    /// (records) following symlinks, so a committed `evaluations -> /outside` or a symlinked skill dir
    /// could read evals from / write records outside the repo. Reject any symlinked component from the
    /// project root to the skill, and any symlinked `evaluations/` / answer / record file.
    private func assertNoSymlinkEscape(skillDir: URL, projectRoot: URL, skillName: String) throws {
        if let link = WorkspaceManager.firstSymlinkOnPath(from: projectRoot, to: skillDir) {
            throw EDDError.invalidArtifact(path: skillName, reason: "skill path crosses a symlink (not allowed): \(link.lastPathComponent)")
        }
        let evaluations = skillDir.appendingPathComponent("evaluations")
        // `SKILL.md` is read (by the lint preflight + eval loader) before staging's symlink check, so it
        // must be guarded here too — a symlinked SKILL.md would otherwise be followed and read first.
        for url in [skillDir.appendingPathComponent("SKILL.md"),
                    evaluations,
                    evaluations.appendingPathComponent("evals.json"),
                    evaluations.appendingPathComponent("trigger-eval.json"),
                    evaluations.appendingPathComponent("benchmark.json"),
                    evaluations.appendingPathComponent("grading.json")]
        where WorkspaceManager.isSymlink(url) {
            throw EDDError.invalidArtifact(path: skillName, reason: "skill path is a symlink (not allowed): \(url.lastPathComponent)")
        }
    }

    /// Keep the gitignored cache gitignored even when `run` is the first skillet command in a repo (no
    /// prior `init`): a self-contained `.skillet/.gitignore` of `*` ignores the whole cache — raw
    /// transcripts/forensics — from within, so a paid run's artifacts can't be accidentally committed
    /// (constitution VI). No-op once present.
    /// Confine the cache the way round 5 confines the skill/`evaluations` paths: reject a symlinked
    /// `.skillet`/`.skillet/runs` **before** writing `.gitignore` or forensics, so a malformed/hostile
    /// repo can't redirect raw traces/records outside the project (constitution VI).
    private func assertCacheNotSymlinked(projectRoot: URL) throws {
        let runsDir = projectRoot.appendingPathComponent(".skillet/runs", isDirectory: true)
        if let link = WorkspaceManager.firstSymlinkOnPath(from: projectRoot, to: runsDir) {
            throw EDDError.invalidArtifact(path: ".skillet", reason: "cache path crosses a symlink (not allowed): \(link.lastPathComponent)")
        }
    }

    private func ensureCacheGitignore(projectRoot: URL) throws {
        let cache = projectRoot.appendingPathComponent(".skillet", isDirectory: true)
        let ignore = cache.appendingPathComponent(".gitignore")
        guard !FileManager.default.fileExists(atPath: ignore.path) else { return }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try "*\n".write(to: ignore, atomically: true, encoding: .utf8)
    }

    /// The free lint gate (design §6.1, constitution V): reuse the shipped error-tier catalog
    /// (`L001`/`L003`; `L009`'s absent/corrupt-evals errors are already owned by `loadEvals` above, so
    /// only its <3-case *warning* can reach here) and **refuse to spend** on an error-tier-invalid skill.
    /// A refusal emits `skillet.lint/1` (under `--json`) and is **exit 2** — a pre-measurement refusal,
    /// distinct from a *measured* non-PASS (exit 1) and from a corrupt/missing-evals artifact (exit 4/2,
    /// which `loadEvals` already enforced). Warnings (incl. a <3-case suite) proceed. `doctor` owns the
    /// broader Phase-2 preflight catalog; `run` only enforces the already-shipped free subset.
    private func runLintPreflight(skillDir: URL, lintConfig: SkilletConfig.Lint, renderer: Renderer, behavioralAxisRuns: Bool = true) throws {
        var report = try lintSkillDirectory(skillDir, config: lintConfig)
        if !behavioralAxisRuns {
            // A run that executes no behavioral evals doesn't need evals.json: SKILL-L009's error
            // must not block a trigger-only skill (F14's "each axis where its file exists"). The
            // SKILL.md-quality rules (L001/L003) still gate — the description is what trigger tests.
            report = LintReport(diagnostics: report.diagnostics.filter { $0.id != "SKILL-L009" })
        }
        guard report.errors > 0 else { return }   // clean or warnings-only → proceed to the paid path
        Console.emit(try renderer.renderLint(report, nextSteps: ["skillet lint  # fix the findings, then re-run"]))
        throw SilentExit(code: ExitCode.usage.rawValue)   // preflight refused before measurement
    }

    private func preflight(_ cases: [EvalCase], skillDir: URL, skillName: String) throws {
        // Fixtures: present + resolvable under the fixture allowlist (resolveFixture rejects absolute /
        // `..` / symlink / hidden, and any evaluations/** that isn't evaluations/fixtures/**).
        for eval in cases {
            for file in eval.files {
                guard let fixture = WorkspaceManager.resolveFixture(file, skillDir: skillDir),
                      FileManager.default.fileExists(atPath: fixture.source.path) else {
                    throw EDDError.invalidArtifact(
                        path: "\(skillName)/evaluations/evals.json",
                        reason: "eval references a fixture that is missing, out-of-skill, symlinked, hidden, or private (only fixtures/** and evaluations/fixtures/** are allowed): \(file)"
                    )
                }
            }
        }
        // Skill bundle: no symlink anywhere in a staged entry (F7 treats symlinks as invalid artifacts).
        for entry in WorkspaceManager.stagedEntries(skillDir: skillDir) {
            if let link = WorkspaceManager.firstSymlink(in: skillDir.appendingPathComponent(entry)) {
                throw EDDError.invalidArtifact(
                    path: "\(skillName)",
                    reason: "skill bundle contains a symlink (not allowed in Phase 1): \(entry)/…/\(link.lastPathComponent)"
                )
            }
        }
    }

    /// The judge slot for a trigger-only run: nothing may be judged (the trigger loop never calls the
    /// judge). Any call is a programmer error surfaced as a thrown failure, never a silent verdict.
    private struct UnjudgedAxisJudge: Judge {
        struct Unjudgeable: Error {}
        func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict {
            throw Unjudgeable()
        }
    }

    private func loadReplayMap() -> [String: Bool] {
        guard let path = replayMap, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
        return (try? JSONDecoder().decode([String: Bool].self, from: data)) ?? [:]
    }

    private func loadBaselineReplayMap() -> [String: Bool] {
        guard let path = replayBaselineMap, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
        return (try? JSONDecoder().decode([String: Bool].self, from: data)) ?? [:]
    }

    // MARK: - spend gate

    /// Confirm spend above the threshold (design P9). `--yes` proceeds; on a TTY we prompt; otherwise
    /// (or `--no-input`, or a declined prompt) we refuse with a usage error carrying the estimate (exit 2).
    private func confirmSpend(trials: Int, estimatedCalls: Int, limit: Int, skill: String) throws {
        guard trials > limit, !yes else { return }
        let estimate = "\(trials) trials (≈ \(estimatedCalls) model calls) for \(skill) exceeds confirm_above_trials=\(limit)"
        if Console.isStdoutTTY() && Console.isStdinTTY() && !noInput {
            FileHandle.standardError.write(Data("\(estimate). Proceed? [y/N] ".utf8))
            let answer = (readLine() ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard answer == "y" || answer == "yes" else {
                throw EDDError.usage(message: "spend not confirmed: \(estimate)", remedy: "re-run with --yes to proceed, or --dry-run to preview")
            }
        } else {
            throw EDDError.usage(message: "spend requires confirmation: \(estimate)", remedy: "re-run with --yes to proceed, or --dry-run to preview")
        }
    }

    // MARK: - records

    /// Write the committed records (the eval-viewer contract + the `pass^k` source of truth) into the
    /// skill's `evaluations/`, and a run summary into the deletable cache. The human commits the
    /// `evaluations/` files (P5 — skillet never auto-commits).
    private func writeRecords(report: RunReport, behavioral: Runner.Outcome?, baseline: [EvalResult]?,
                              trigger: [TriggerEvalResult]?,
                              skillDir: URL, harness: String, k: Int, provenance: RunProvenance, base: URL) throws {
        let evalDir = skillDir.appendingPathComponent("evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // benchmark.json is latest-run-**per-axis** (F14): the axis that didn't run this invocation is
        // carried from the previously committed file, so a --axis trigger run can't destroy the
        // behavioral record (or vice versa). An unreadable prior is treated as absent, never fatal.
        let benchmarkURL = evalDir.appendingPathComponent("benchmark.json")
        let prior = (try? Data(contentsOf: benchmarkURL)).flatMap { try? JSONDecoder().decode(BenchmarkFile.self, from: $0) }
        try encoder.encode(BenchmarkFile(
            skill: report.skill,
            behavioral: behavioral.map { (report: report, evals: $0.evals) },
            baseline: baseline,
            trigger: trigger, harness: harness, k: k, provenance: provenance, preserving: prior
        )).write(to: benchmarkURL)
        // grading.json is judge output — written only when the behavioral axis ran (a trigger-only
        // run has no verdicts and must not blank the committed grading record).
        if let behavioral {
            try encoder.encode(GradingFile(evals: behavioral.evals, provenance: provenance))
                .write(to: evalDir.appendingPathComponent("grading.json"))
        }
        if let runJSON = try? SkilletJSON.encode(report) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try? Data(runJSON.utf8).write(to: base.appendingPathComponent("run.json"))
        }
    }

    /// Onboarding: after a run, the human commits the records (P5); later loop verbs land in Phase 2.
    /// The suggestion names only files this run actually wrote — a trigger-only run produces no
    /// grading.json (nothing was judged), so it must not tell the user to commit one (round 3, P2).
    static func nextSteps(wroteGrading: Bool = true) -> [String] {
        let registered = Set(SkilletCommand.configuration.subcommands.compactMap { $0.configuration.commandName })
        let verbs = ["next", "iterate"].filter { registered.contains($0) }.map { "skillet \($0)" }
        guard verbs.isEmpty else { return verbs }
        return [wroteGrading ? "commit evaluations/benchmark.json + grading.json" : "commit evaluations/benchmark.json"]
    }
}
