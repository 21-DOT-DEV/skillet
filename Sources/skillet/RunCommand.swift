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

    @Option(name: .customLong("judge"), help: "Grader for behavioral evals: text-judge (default) or grounded-judge (reads produced-file contents to catch created-but-wrong).")
    var judgeSelection: String = TextJudge.id   // named `judgeSelection` (not `judge`) so it never shadows the `judge` config/param inside buildAdapterAndJudge

    // Hidden test-only offline wiring (ReplayAdapter + ReplayJudge); the public --record/--replay is F19.
    //
    // **What an offline run of `--axis trigger` does and does not measure.** That axis asks whether a
    // model, given a prompt and a shelf of skills, reaches for the right one. No model runs here, so
    // nothing offline can answer that. What it measures is everything around the answer: that the shelf
    // is assembled correctly, that the skill reported as reached-for is read back correctly, that
    // pass and fail are computed from it, and that the records merge. The answer itself is stated by the
    // skill's own frontmatter (`replay-fires: true`), so a test asserts on something it declared rather
    // than on a name. Checking the stand-in against a real session is separate work — `F74`.
    @Flag(name: .long, help: ArgumentHelp("Test-only offline replay wiring.", visibility: .private))
    var replay = false
    @Option(name: .customLong("replay-map"), help: ArgumentHelp("Test-only replay verdict map (criterion→bool JSON).", visibility: .private))
    var replayMap: String?
    @Option(name: .customLong("replay-baseline-map"), help: ArgumentHelp("Test-only baseline-arm replay verdict map (criterion→bool JSON).", visibility: .private))
    var replayBaselineMap: String?

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            // Before anything else: hidden options are refused outright unless the suite enabled them.
            // The offline switch matters most — it swaps real grading for canned verdicts, so reaching it
            // from an ordinary command line would let a failing quality gate report success.
            if replay { try TestSeam.assertEnabled("--replay") }
            if replayMap != nil { try TestSeam.assertEnabled("--replay-map") }
            if replayBaselineMap != nil { try TestSeam.assertEnabled("--replay-baseline-map") }
            try TestSeam.assertRecordingsUsable(
                replay: replay,
                provided: [replayMap.map { _ in "--replay-map" },
                           replayBaselineMap.map { _ in "--replay-baseline-map" }])
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
            guard let root = context.root.map({ URL(fileURLWithPath: $0) }) else {
                throw EDDError.projectNotFound(cwd: context.cwd)
            }

            let config = try loadConfig(options: options, context: context)
            let runsCfg = config?.runs ?? .init()
            let judgeCfg = config?.judge ?? .init()
            let skillsRoot = config?.project?.skillsRoot ?? "skills"
            // Every number a measurement runs on, resolved and checked in the one place both paid
            // commands call — and handed back as a value the model-wiring step demands, so neither can
            // reach a paid call with something unchecked. Stays here, ahead of finding the skill, so a
            // mistyped flag still answers before anything about the state of the project.
            let approved = try SpendGate.approveSettings(runsCfg, runsFlag: runs)
            let k = approved.k

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
            // Free-before-paid (constitution V), in ONE place both paid commands call: a missing /
            // out-of-skill / symlinked fixture, an eval with nothing to grade, a symlink inside the
            // bundle, and the error-tier lint catalog — all refused before any dry-run/spend/probe.
            // Axis-aware: passing `cases` (nil on a trigger-only run) is what relaxes the has-evals rule,
            // so the two can't disagree about whether behavioral evals are running (F14 review).
            try SpendGate.assertFreeChecksPass(
                cases: cases, skillDir: skillDir, skillName: skillName,
                lintTarget: skillDir, lintConfig: config?.lint ?? .init(), renderer: renderer)
            if triggerCases != nil {
                // The trigger axis stages a frontmatter-only stub of the target — verify the fence
                // extracts BEFORE any spend, or every trial would be an unmeasured staging failure.
                // Safe read (F33 security pass): the previous unguarded `String(contentsOf:)` meant a
                // FIFO SKILL.md hung here pre-spend (and a refused read mislabeled as "no fence").
                let markdown: String
                switch SafeFile.readPlainText(skillDir.appendingPathComponent("SKILL.md"), cap: 1 << 20) {
                case let .success(text): markdown = text
                case let .failure(refusal):
                    throw refusal.rejection(path: "\(skillName)/SKILL.md", saying: "SKILL.md ")
                }
                guard WorkspaceManager.frontmatterStub(markdown: markdown) != nil else {
                    throw EDDError.invalidArtifact(
                        path: "\(skillName)/SKILL.md",
                        reason: "no frontmatter fence — the trigger axis stages a frontmatter-only stub, so SKILL.md must open with a `---` block"
                    )
                }
            }
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
            // F16: validate the grader selection early (before any spend/dry-run), and warn on the
            // grounded grader's larger, pricier grading requests (P9 spend-honesty — the trial/call
            // counts don't change, so the note is the honest signal until F60 parses real tokens).
            guard judgeSelection == TextJudge.id || judgeSelection == GroundedJudge.id else {
                throw EDDError.usage(
                    message: "unknown judge '\(judgeSelection)'",
                    remedy: "use --judge \(TextJudge.id) (default) or --judge \(GroundedJudge.id)"
                )
            }
            if judgeSelection == GroundedJudge.id {
                if cases != nil {
                    Console.emit(Rendering(stderr: "note: grounded judge includes file contents — larger grading requests, higher per-call cost (up to ~128 KiB of file text each)\n"))
                } else {
                    // Grounded is behavioral-only; on a trigger-only run it has no effect. Say so rather
                    // than silently ignoring the flag (post-ship review finding 4).
                    Console.emit(Rendering(stderr: "note: --judge \(GroundedJudge.id) applies to behavioral evals; none are running, so it has no effect (the trigger axis is judge-free)\n"))
                }
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
                    confirmAboveTrials: approved.confirmAboveTrials,
                    requiresConfirmation: trials > approved.confirmAboveTrials, willSpend: !replay,
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
            try confirmSpend(trials: trials, estimatedCalls: estimatedCalls, limit: approved.confirmAboveTrials, skill: skillName)

            // Assemble the harness + judge; probe before spending so a missing/banned binary fails fast (3).
            // Trigger-only runs are judge-free (deterministic grading): no judge is built and
            // `judge.model`'s required-explicit rule (§14-4) doesn't apply — nothing gets judged.
            let backend = try buildAdapterAndJudge(
                config: config, judge: judgeCfg, approved: approved,
                needsJudge: cases != nil, projectRoot: root
            )
            // The shared before-you-spend gate (F41 extracted it so a paid command cannot forget it).
            // Strict for the paid path (refuse banned/unauth before spend); replay's probe is canned and
            // free — probed anyway so the executor's version is stamped into the records (M3 provenance).
            let harnessInfo = try await SpendGate.assertHarnessReady(backend.adapter, strict: !replay)
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
            // One call: the shared routine confines the path, refuses a file where the folder belongs,
            // ensures the self-ignoring rule, and creates the directory.
            try ensureCacheGitignore(projectRoot: root)
            // **The whole identifier, not the first eight characters of it.** Eight hex characters is a
            // birthday bound on thirty-two bits, and the second-resolution timestamp beside it narrows the
            // window without removing it — several runs starting in the same second is ordinary on a build
            // machine. What makes it worth removing is how a clash fails: asking for a folder that already
            // exists succeeds silently, so the second run would write its transcripts, traces and records
            // into the first run's folder, and preparing a workspace there deletes what is already in it.
            // Measured: creating an existing folder returns success and leaves the earlier file in place.
            //
            // The throwaway-copy path already uses the whole identifier for the same reason, and it is the
            // *safer* of the two — a clash there is refused outright rather than silently accepted.
            let stamp = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
            let base = root.appendingPathComponent(".skillet/runs/\(stamp)", isDirectory: true)
            let runner = Runner(adapter: backend.adapter, judge: backend.judge, evidencePolicy: backend.evidencePolicy)
            let behavioralOutcome: Runner.Outcome? = if let cases {
                try await runner.run(
                    skill: skillRef, evals: cases, k: k,
                    injection: .only(load: [skillRef]), base: base, keepWorkspace: keepWorkspace
                )
            } else { nil }
            // The baseline arm (F15): same evals, same judge + rubric (A1 — that IS the
            // comparison), `SkillSet.none` — nothing staged, isolation switch on, tripwire armed.
            let baselineResults: [EvalResult]? = if ab, let cases {
                await Runner(adapter: backend.adapter, judge: backend.baselineJudge, evidencePolicy: backend.evidencePolicy)
                    .runBaseline(skill: skillRef, evals: cases, k: k, base: base, keepWorkspace: keepWorkspace)
            } else { nil }
            // The trigger axis (F14, §9.3): bare queries against whole-corpus frontmatter stubs,
            // fired/not-fired judged deterministically from skillInvocations — one call per trial.
            let triggerResults: [TriggerEvalResult]? = if let triggerCases {
                await runner.runTrigger(
                    target: skillRef,
                    corpus: discovered.map { SkillRef(name: $0.lastPathComponent, path: $0.path) },
                    // The folder every candidate skill lives under — the point each staged file's whole
                    // path is proved clean from, on every attempt rather than once per run.
                    skillsRoot: root.appendingPathComponent(skillsRoot),
                    cases: triggerCases, k: k, base: base, keepWorkspace: keepWorkspace
                )
            } else { nil }

            let report = try RunReport(
                skill: skillName,
                results: behavioralOutcome?.evals ?? [],
                trigger: triggerResults,
                baseline: baselineResults
            )
            // Stamp the ACTUAL judge backend + executor version in records (not configured values) —
            // P3 review fix + M3 provenance: re-grade and harness-vs-skill attribution need the truth.
            let provenance = RunProvenance(
                judgeId: backend.id, judgeProvider: backend.provider, judgeModel: backend.model,
                judgePromptVersion: backend.promptVersion,
                executorBinaryVersion: harnessInfo.version.isEmpty ? "unknown" : harnessInfo.version
            )
            try writeRecords(report: report, behavioral: behavioralOutcome, baseline: baselineResults,
                             trigger: triggerResults,
                             skillDir: skillDir, projectRoot: root, harness: backend.adapter.id.rawValue, k: k,
                             provenance: provenance, base: base)

            Console.emit(try renderer.renderRun(report, nextSteps: Self.nextSteps(wroteGrading: behavioralOutcome != nil)))
            // **You asked for a comparison and did not get one.** When the switched-off arm yields no
            // usable pairing at all — every trial failed, or a skill fired where none may exist — the
            // comparison is void: nothing in it can be trusted, which is the settled rule for a trust
            // check failing in a controlled experiment. Exit `3` rather than `1`, because no test failed;
            // what failed is this machine's ability to provide a clean switched-off measurement, and
            // that is already what `3` means here — the free pre-spend check for the same inability
            // leaves `3` too (design §6.1). One fault, one answer, whichever check catches it.
            if let ab = report.ab, ab.producedNoPairing {
                throw EDDError.harnessNotFound(
                    harness: backend.adapter.id.rawValue,
                    reason: "the without-skill comparison produced no usable pairing"
                        + (ab.polluted > 0
                            ? " — \(ab.polluted) baseline trial(s) had a skill fire where none may exist, so isolation failed on this machine"
                            : " — every baseline trial failed to run")
                        + "; the with-skill results were still written, but no comparison can be drawn from them")
            }
            // pass^k demands all k trials pass — on every axis that ran (exit 1 on any non-PASS).
            // **A check that graded nothing is not a check that failed.** `passed` counts only checks
            // where every graded attempt passed, so anything not passing used to count against the skill —
            // including a check where nothing was ever graded, which says nothing about the skill at all.
            // Comparing against the checks that actually produced a result keeps a genuine failure failing
            // while stopping a rate limit from being reported as a regression.
            let behavioralMeasured = report.evals.filter { $0.recorded > 0 }.count
            let behavioralFailed = behavioralMeasured > report.passed
            let triggerFailed = report.trigger.map { axis in
                axis.passed < axis.evals.filter { $0.recorded > 0 }.count
            } ?? false
            if behavioralFailed || triggerFailed {
                throw SilentExit(code: ExitCode.measuredFailure.rawValue)
            }
            // **Nothing failed, but something could not be measured.** A measured failure above wins,
            // because it is real information about the skill. Reaching here means every graded attempt
            // passed and some attempt never got graded — a rate limit, a grader error, a dropped
            // connection. That used to be recorded as the skill failing and left `1`, telling a pipeline
            // the skill had regressed. `75` is the long-standing number for "temporary failure, try again
            // later", and is deliberately not the environment number, which never comes right on a retry.
            // **An unusable cost report is said out loud.** The figures are dropped so a part-read total
            // never enters the record; saying nothing about it made that indistinguishable from a run that
            // simply reported no figures. Not a failure — the measurement itself is unaffected — so it is
            // a note rather than a different exit number.
            if report.costUnreadable > 0 {
                Console.emit(Rendering(stderr: "note: \(report.costUnreadable) attempt(s) reported what "
                    + "they cost in a form this tool could not read, so no cost is recorded for them — the "
                    + "measurements themselves are unaffected\n"))
            }
            if report.ungraded > 0 {
                Console.emit(Rendering(stderr: "note: \(report.ungraded) attempt(s) were never graded, so "
                    + "they are left out of the scores above rather than counted as failures — see the "
                    + "ungraded_reason beside each attempt for why\n"))
                throw SilentExit(code: ExitCode.temporaryFailure.rawValue)
            }
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        } catch let error as SilentExit {
            throw error
        } catch {
            // Same three-way rule as the drafting command: anything we did not anticipate is our bug,
            // reported as such rather than blamed on the project. Previously these escaped unhandled,
            // producing an undocumented exit code.
            let classified = EDDError.internalError(detail: "\(error)")
            Console.emit(renderer.renderError(classified))
            throw SilentExit(code: classified.exitCode.rawValue)
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
        catch {
            throw EDDError.invalidArtifact(path: "\(skillName)/evaluations/evals.json",
                                           reason: "not valid evals.json — \(DecodeFailure.describe(error))")
        }
        let cases = evalsFile.cases
        guard !cases.isEmpty else {
            // Present-but-empty skips the axis under the default mode — symmetric with the trigger
            // side's empty handling, and what an init-scaffolded skeleton contains (round 5, P1).
            guard required else { return nil }
            throw EDDError.usage(message: "no evals to run for \(skillName)", remedy: "add at least one eval to evaluations/evals.json")
        }
        // The "nothing to grade" refusal moved to the shared pre-spend routine, with the fixture and
        // bundle checks it belongs beside — see `SpendGate.assertFreeChecksPass`.
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
    /// The wiring this command needs. **The shared part is chosen elsewhere** — which program answers,
    /// which grader marks, and the refusals that go with them all live in ``MeasurementSetup`` so a second
    /// measuring command cannot end up disagreeing with this one. What stays here are the two branches
    /// only this command has: a second grader for the switched-off arm, and the deterministic axis that
    /// needs no grader at all. **The order is unchanged** — offline is decided before the grader-free
    /// axis, exactly as before, because a replayed trigger-only run took the offline path.
    private func buildAdapterAndJudge(
        config: SkilletConfig?, judge judgeCfg: SkilletConfig.Judge, approved: SpendGate.Approved,
        needsJudge: Bool = true, projectRoot: URL
    ) throws -> (adapter: any HarnessAdapter, judge: any Judge, baselineJudge: any Judge, id: String, provider: String, model: String, promptVersion: String, evidencePolicy: EvidencePolicy) {
        if replay {
            let wiring = try MeasurementSetup.forBehaviour(
                config: config, judge: judgeCfg, approved: approved, judgeSelection: judgeSelection,
                offline: .init(verdicts: try loadReplayMap(projectRoot), defaultPass: replayMap == nil))
            // The switched-off arm defaults to failing everything, so a replayed comparison shows a
            // deterministic positive difference; a test may override either arm's recording.
            return (wiring.adapter, wiring.judge,
                    ReplayJudge(try loadBaselineReplayMap(projectRoot), defaultPass: false),
                    wiring.id, wiring.provider, wiring.model, wiring.promptVersion, wiring.policy)
        }
        // Deterministic axis: grading needs no grader, and the provenance says "none" honestly.
        if !needsJudge {
            let claudePath = config?.harness?.claudeCode?.path
            let adapter = ClaudeCodeAdapter(configPath: claudePath, timeout: approved.timeout,
                                            outputLimitBytes: approved.outputLimitBytes)
            return (adapter, UnjudgedAxisJudge(), UnjudgedAxisJudge(), "none", "none", "none", "none", .listingOnly)
        }
        let wiring = try MeasurementSetup.forBehaviour(
            config: config, judge: judgeCfg, approved: approved, judgeSelection: judgeSelection,
            offline: nil)
        // Both arms share one grader when it is real.
        return (wiring.adapter, wiring.judge, wiring.judge, wiring.id, wiring.provider, wiring.model,
                wiring.promptVersion, wiring.policy)
    }

    /// Validate that every declared eval fixture (`files[]`, resolved against the skill directory)
    /// exists, before any spend — a missing fixture is a clear artifact error, not a silent skip.
    /// Confine the skill's own I/O paths: the skill dir + `evaluations/` are read (evals) and written
    /// (records) following symlinks, so a committed `evaluations -> /outside` or a symlinked skill dir
    /// could read evals from / write records outside the repo. Reject any symlinked component from the
    /// project root to the skill, and any symlinked `evaluations/` / answer / record file.
    private func assertNoSymlinkEscape(skillDir: URL, projectRoot: URL, skillName: String) throws {
        if let link = WorkspaceManager.firstSymlinkOnPath(from: projectRoot, to: skillDir) {
            throw EDDError.invalidArtifact(path: skillName, reason: "skill path crosses a symlink (not allowed): \(link.lastPathComponent)",
                                           fix: "replace the symbolic link with a real folder — a link could send this outside the project, where the checks that keep it undoable do not reach")
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
            throw EDDError.invalidArtifact(path: skillName, reason: "skill path is a symlink (not allowed): \(url.lastPathComponent)",
                                           fix: "replace the symbolic link with a real folder — a link could send this outside the project, where the checks that keep it undoable do not reach")
        }
    }

    /// Refuse a record path that has become a link since the command started. Named separately from the
    /// start-of-command check because it answers a different question: not "was this safe when we began"
    /// but "is it safe in the instant before we write".
    static func assertNoLinkOnPath(to url: URL, projectRoot: URL, label: String) throws {
        if let link = SafeFile.firstSymlinkOnPath(from: projectRoot, to: url) {
            throw EDDError.invalidArtifact(
                path: label,
                reason: "the path to this record became a link while the run was measuring: \(link.lastPathComponent)",
                fix: "replace the link with a real folder or file — a link could send this run's results "
                    + "outside the project, where nothing here can reach them")
        }
    }

    /// Keep the gitignored cache gitignored even when `run` is the first skillet command in a repo (no
    /// prior `init`): a self-contained `.skillet/.gitignore` of `*` ignores the whole cache — raw
    /// transcripts/forensics — from within, so a paid run's artifacts can't be accidentally committed
    /// (constitution VI). No-op once present.
    /// Confine the cache the way round 5 confines the skill/`evaluations` paths: reject a symlinked
    /// `.skillet`/`.skillet/runs` **before** writing `.gitignore` or forensics, so a malformed/hostile
    /// repo can't redirect raw traces/records outside the project (constitution VI).

    /// Delegates to the shared cache preparation (F41 extracted it) so this command and `suggest`
    /// cannot have one set of safety checks between them — which is how a plain file sitting where the
    /// cache folder belongs came to be unguarded in both.
    private func ensureCacheGitignore(projectRoot: URL) throws {
        try CacheSupport.prepareCacheDirectory(projectRoot: projectRoot, subdirectory: "runs")
    }

    /// The judge slot for a trigger-only run: nothing may be judged (the trigger loop never calls the
    /// judge). Any call is a programmer error surfaced as a thrown failure, never a silent verdict.
    private struct UnjudgedAxisJudge: Judge {
        struct Unjudgeable: Error {}
        func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict {
            throw Unjudgeable()
        }
    }

    // Operator-supplied replay-map paths (hidden test seam) read through the one sanctioned untrusted
    // reader (T2): bounds a pathological file and refuses a symlink / special / hard-linked path, matching
    // every other file read. A file that was named and cannot be used is refused rather than treated as
    // empty — see ``decodeVerdictMap(_:projectRoot:)`` for why that difference decides a verdict.
    private func loadReplayMap(_ projectRoot: URL) throws -> [String: Bool] {
        try Self.decodeVerdictMap(replayMap, projectRoot: projectRoot)
    }

    private func loadBaselineReplayMap(_ projectRoot: URL) throws -> [String: Bool] {
        try Self.decodeVerdictMap(replayBaselineMap, projectRoot: projectRoot)
    }

    /// **Confined to the project**, like every other read here — unconfined, these hidden options read any
    /// regular file on the machine. Shared with the proving command, which reads the same recordings.
    ///
    /// **A file that was named and cannot be used is refused, not quietly treated as empty.** Falling back
    /// to an empty set of recorded answers looks harmless and is not: with no recorded answer for any
    /// check, every check fails, in *both* of the two measurements the proving command compares. Nothing
    /// then scores lower than anything else, so the edit is declared proven and the command prints the
    /// line telling you to apply it — off a run where not one check passed and the named file was never
    /// read. Reproduced end to end: naming a file that is not there printed `0/1 → 0/1`, "no test scored
    /// lower", and an offer to land the edit.
    ///
    /// **A relative name is taken as relative to the project**, the same as the draft file the proving
    /// command reads. It used to be taken as relative to whatever folder the command was invoked from, so
    /// running from elsewhere silently looked somewhere else — and, before the refusal above, said
    /// nothing when it found nothing.
    static func decodeVerdictMap(_ path: String?, projectRoot: URL) throws -> [String: Bool] {
        guard let path else { return [:] }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
                                      : projectRoot.appendingPathComponent(path)
        guard case let .success(text) = SafeFile.readConfinedRegularText(url, base: projectRoot, cap: 1 << 20)
        else {
            throw EDDError.invalidArtifact(
                path: path,
                reason: "the recorded answers named here could not be read from inside the project",
                fix: "give a path to a readable file inside the project — with none, every check fails in "
                    + "both measurements and an edit that proves nothing reads as proven")
        }
        guard let decoded = try? JSONDecoder().decode([String: Bool].self, from: Data(text.utf8)) else {
            throw EDDError.invalidArtifact(
                path: path,
                reason: "the recorded answers are not a set of check-name to true-or-false entries",
                fix: #"write it as {"a criterion": true, "another": false}"#)
        }
        return decoded
    }

    // MARK: - spend gate

    /// Confirm spend above the threshold (design P9). The asking is shared (`SpendGate.confirmCost`); the
    /// **refusal stays here**, because this command leaves `2` for a decline while the proving command
    /// leaves `5`, and moving the error into the shared routine would have changed this one silently.
    private func confirmSpend(trials: Int, estimatedCalls: Int, limit: Int, skill: String) throws {
        switch SpendGate.confirmCost(trials: trials, estimatedCalls: estimatedCalls, limit: limit,
                                     skill: skill, yes: yes, noInput: noInput) {
        case .proceed:
            return
        case let .declined(estimate):
            throw EDDError.usage(message: "spend not confirmed: \(estimate)", remedy: "re-run with --yes to proceed, or --dry-run to preview")
        case let .notAsked(estimate):
            throw EDDError.usage(message: "spend requires confirmation: \(estimate)", remedy: "re-run with --yes to proceed, or --dry-run to preview")
        }
    }

    // MARK: - records

    /// Write the committed records (the eval-viewer contract + the `pass^k` source of truth) into the
    /// skill's `evaluations/`, and a run summary into the deletable cache. The human commits the
    /// `evaluations/` files (P5 — skillet never auto-commits).
    private func writeRecords(report: RunReport, behavioral: Runner.Outcome?, baseline: [EvalResult]?,
                              trigger: [TriggerEvalResult]?,
                              skillDir: URL, projectRoot: URL, harness: String, k: Int,
                              provenance: RunProvenance, base: URL) throws {
        let evalDir = skillDir.appendingPathComponent("evaluations", isDirectory: true)
        // **Checked before the folder is made, as well as before the file is written.**
        //
        // This narrows the gap; it does not close it, and saying otherwise would be worse than the gap.
        // Checking a name and then acting on it can never be made safe by checking harder — the standard
        // remedy is a single operation that refuses links as part of doing the work, which the file
        // routines used here do not offer. Measured, the harm reported for this gap does not actually
        // occur on this machine: making a folder whose name has been replaced by a link either fails
        // outright or creates nothing. But that is the platform's behaviour rather than a promise this
        // code makes, and this project builds for another platform with a separate implementation.
        try Self.assertNoLinkOnPath(to: evalDir, projectRoot: projectRoot, label: "evaluations")
        try FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // benchmark.json is latest-run-**per-axis** (F14): the axis that didn't run this invocation is
        // carried from the previously committed file, so a --axis trigger run can't destroy the
        // behavioral record (or vice versa). An unreadable prior is treated as absent, never fatal.
        let benchmarkURL = evalDir.appendingPathComponent("benchmark.json")
        // Safe read (F33 security pass): the prior is repo-controlled; a planted FIFO benchmark.json
        // previously hung the record-writer AFTER spend. A refusal reads as absent — the atomic write
        // below then REPLACES the planted entry (rename, never opened): the self-healing path.
        let priorData: Data? = { if case let .success(d) = SafeFile.readPlainData(benchmarkURL, cap: 8 << 20) { return d } else { return nil } }()
        let prior = priorData.flatMap { try? JSONDecoder().decode(BenchmarkFile.self, from: $0) }
        // **Said again here, because the file can change after it was checked.** It is read once before
        // anything is spent — where an unreadable one is announced and an unscorable one stops the run —
        // and again now, minutes later. Anything could have replaced it in between. Whoever did that has
        // already destroyed whatever it held, so nothing recoverable is lost by writing over it; what
        // would be lost is the person ever knowing, which is why it is said rather than passed over.
        if priorData != nil, prior == nil {
            Console.emit(Rendering(stderr: "note: evaluations/benchmark.json could not be read when this "
                + "run went to write its results, and has been replaced — it was readable when the run "
                + "started, so something changed it in between.\n"))
        }
        let encoded = try encoder.encode(BenchmarkFile(
            skill: report.skill,
            behavioral: behavioral.map { (report: report, evals: $0.evals) },
            baseline: baseline,
            trigger: trigger, harness: harness, k: k, provenance: provenance, preserving: prior
        ))
        // **Checked immediately before writing, not only at the start of the command.** The check at the
        // start runs before a measurement that takes minutes, which is a long and predictable window in
        // which to plant a link. Measured on this platform, an atomic write replaces a link rather than
        // following it — so the outcome would be safe here — but that is undocumented behaviour, it
        // differs by platform, and this project supports one it is not tested on. An explicit guard costs
        // nothing and does not rely on being lucky.
        try Self.assertNoLinkOnPath(to: benchmarkURL, projectRoot: projectRoot, label: "benchmark.json")
        try encoded.write(to: benchmarkURL, options: [.atomic])
        // grading.json is judge output — written only when the behavioral axis ran (a trigger-only
        // run has no verdicts and must not blank the committed grading record).
        if let behavioral {
            // **The same last-instant check as the file above.** Both are committed records written into
            // the same folder at the same moment, and only one of them was checked — so a link planted on
            // that folder during the minutes a measurement takes was refused for one file and not for the
            // other, in the window the note above exists to close.
            let gradingURL = evalDir.appendingPathComponent("grading.json")
            try Self.assertNoLinkOnPath(to: gradingURL, projectRoot: projectRoot, label: "grading.json")
            try encoder.encode(GradingFile(evals: behavioral.evals, provenance: provenance))
                .write(to: gradingURL, options: [.atomic])
        }
        // **This one is allowed to fail quietly, and that is the whole of the reason.** It writes a
        // diagnostic copy of the run into the folder this tool documents as safe to delete at any time.
        // Nothing reads it back — the committed records above are the source of truth, and the score
        // re-derives from those. A failure here therefore costs a convenience and nothing else, which is
        // why it does not stop a run that has already been paid for. Written down because two separate
        // reviews have asked.
        if let runJSON = try? SkilletJSON.encode(report) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try? Data(runJSON.utf8).write(to: base.appendingPathComponent("run.json"), options: [.atomic])
        }
    }

    /// Onboarding: after a run, the human commits the records (P5); later loop verbs land in Phase 2.
    /// The suggestion names only files this run actually wrote — a trigger-only run produces no
    /// grading.json (nothing was judged), so it must not tell the user to commit one (round 3, P2).
    static func nextSteps(wroteGrading: Bool = true) -> [String] {
        // **Deliberately asked of the binary rather than written down.** The list names the loop verbs a
        // reader should reach for next, and filters to those the tool actually answers to — so a verb
        // that has not shipped is never suggested, and one that ships later needs no edit here. `next`
        // is in the list and is not registered today: it appears the moment it does, which is the intent
        // rather than an oversight, and a test pins both halves.
        let registered = Set(SkilletCommand.configuration.subcommands.compactMap { $0.configuration.commandName })
        let verbs = ["next", "iterate"].filter { registered.contains($0) }.map { "skillet \($0)" }
        // **Committing comes first, and is not replaced by the loop verbs.** This used to hand over the
        // loop verb *instead* of the commit advice the day one was registered — but a run writes its
        // records into tracked files, so the tree is dirty, and `iterate` refuses a dirty repository.
        // The suggested next step would have refused the moment you followed it. They are sequential,
        // not alternatives: commit what was measured, then prove an edit against it.
        let commit = wroteGrading ? "commit evaluations/benchmark.json + grading.json"
                                  : "commit evaluations/benchmark.json"
        return [commit] + verbs
    }
}
