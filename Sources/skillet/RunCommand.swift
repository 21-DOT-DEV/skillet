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
        Runs each eval in evaluations/evals.json k times in a fresh sandbox, judges every expectation \
        against the run's response + post-run files, and prints a PASS/FAIL/FLAKY table with aggregate \
        pass^k (at observed k = the min recorded trials across evals). Estimates the trial count first \
        and won't spend above runs.confirm_above_trials without --yes; --dry-run previews the plan. \
        Writes evaluations/benchmark.json + grading.json (commit these); pass^k re-derives from them.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "The skill to run; defaults to the only skill when exactly one is discovered.")
    var skill: String?

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

    // Hidden test-only offline wiring (ReplayAdapter + ReplayJudge); the public --record/--replay is F19.
    @Flag(name: .long, help: ArgumentHelp("Test-only offline replay wiring.", visibility: .private))
    var replay = false
    @Option(name: .customLong("replay-map"), help: ArgumentHelp("Test-only replay verdict map (criterion→bool JSON).", visibility: .private))
    var replayMap: String?

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
            guard let root = context.root.map({ URL(fileURLWithPath: $0) }) else {
                throw EDDError.projectNotFound(cwd: context.cwd)
            }

            let config = try loadConfig(options: options)
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

            // Decode the evals: absent/empty → usage (2); present-but-corrupt → artifact (4).
            let cases = try loadEvals(skillDir: skillDir, skillName: skillName)
            // Fail loud on a missing/out-of-skill/symlinked fixture or bundle symlink before spending.
            try preflight(cases, skillDir: skillDir, skillName: skillName)
            // Free-before-paid (constitution V): refuse a lint-error skill before any dry-run/spend/probe.
            try runLintPreflight(skillDir: skillDir, lintConfig: config?.lint ?? .init(), renderer: renderer)

            // Spend estimate + gate (design P9). --dry-run previews and spends nothing.
            let trials = cases.count * k
            if dryRun {
                let plan = RunPlan(
                    skill: skillName, evals: cases.count, k: k, trials: trials,
                    confirmAboveTrials: runsCfg.confirmAboveTrials,
                    requiresConfirmation: trials > runsCfg.confirmAboveTrials, willSpend: !replay
                )
                if options.json {
                    Console.emit(Rendering(stdout: try SkilletJSON.encode(plan) + "\n"))
                } else {
                    Console.emit(Rendering(stdout: "plan: \(cases.count) eval(s) × k=\(k) = \(trials) trial(s) for \(skillName) (nothing spent)\n"))
                }
                return
            }
            try confirmSpend(trials: trials, limit: runsCfg.confirmAboveTrials, skill: skillName)

            // Assemble the harness + judge; probe before spending so a missing/banned binary fails fast (3).
            let timeout = DurationString.parse(runsCfg.timeout) ?? .seconds(600)
            let backend = try buildAdapterAndJudge(config: config, judge: judgeCfg, timeout: timeout, outputLimitBytes: runsCfg.maxOutputBytes)
            if !replay { _ = try await backend.adapter.probe(strict: true) }   // refuse banned/unauth before spend

            let skillRef = SkillRef(name: skillName, path: skillDir.path)
            try assertCacheNotSymlinked(projectRoot: root)   // confine cache writes to the repo (no symlink escape)
            try ensureCacheGitignore(projectRoot: root)   // keep the cache gitignored even without prior `init`
            // Second-resolution timestamp + a short uuid so two runs in the same second never share a path.
            let stamp = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
            let base = root.appendingPathComponent(".skillet/runs/\(stamp)", isDirectory: true)
            let outcome = try await Runner(adapter: backend.adapter, judge: backend.judge).run(
                skill: skillRef, evals: cases, k: k,
                injection: .only(load: [skillRef]), base: base, keepWorkspace: keepWorkspace
            )
            // Stamp the ACTUAL judge backend in records (not the configured value) — P3 review fix.
            try writeRecords(outcome: outcome, skillDir: skillDir, harness: backend.adapter.id.rawValue, k: k,
                             judge: SkilletConfig.Judge(provider: backend.provider, model: backend.model), base: base)

            Console.emit(try renderer.renderRun(outcome.report, nextSteps: Self.nextSteps()))
            // pass^k demands all k trials pass: any FAIL or FLAKY is a measured failure (exit 1).
            if outcome.report.passed < outcome.report.evals.count {
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

    private func loadEvals(skillDir: URL, skillName: String) throws -> [EvalCase] {
        let raw = try SkillReader().read(skillDirectory: skillDir)
        guard let data = raw.evalsJSON else {
            throw EDDError.usage(message: "no evals to run for \(skillName)", remedy: "add evaluations/evals.json (see `skillet init`)")
        }
        let evalsFile: EvalsFile
        do { evalsFile = try JSONDecoder().decode(EvalsFile.self, from: data) }
        catch { throw EDDError.invalidArtifact(path: "\(skillName)/evaluations/evals.json", reason: "not valid evals.json") }
        let cases = evalsFile.cases
        guard !cases.isEmpty else {
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

    /// The harness adapter + judge, plus the **actual** judge `provider`/`model` for record stamping.
    /// Production: `claude-code` adapter + a `claude`-CLI-backed text judge (binary resolved once,
    /// shared by both). Tests: the offline replay wiring. An unsupported `judge.provider` fails fast
    /// rather than silently running claude-code while records claim otherwise (P3 review fix).
    private func buildAdapterAndJudge(
        config: SkilletConfig?, judge judgeCfg: SkilletConfig.Judge, timeout: Duration, outputLimitBytes: Int
    ) throws -> (adapter: any HarnessAdapter, judge: any Judge, provider: String, model: String) {
        if replay {
            return (ReplayAdapter(), ReplayJudge(loadReplayMap(), defaultPass: replayMap == nil), "replay", "replay")
        }
        guard judgeCfg.provider == "claude-code" else {
            throw EDDError.usage(
                message: "judge.provider '\(judgeCfg.provider)' is not supported in Phase 1",
                remedy: "set judge.provider: claude-code in skillet.yaml (the only implemented provider)"
            )
        }
        let claudePath = config?.harness?.claudeCode?.path
        guard let resolved = BinaryResolver().resolve(flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: claudePath, pathName: "claude") else {
            throw EDDError.harnessNotFound(harness: "claude-code")
        }
        let adapter = ClaudeCodeAdapter(configPath: claudePath, timeout: timeout, outputLimitBytes: outputLimitBytes)
        let judge = TextJudge(runner: ClaudeCLIJudgeRunner(binaryPath: resolved.path), model: judgeCfg.model)
        return (adapter, judge, "claude-code", judgeCfg.model)
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
    private func runLintPreflight(skillDir: URL, lintConfig: SkilletConfig.Lint, renderer: Renderer) throws {
        let report = try lintSkillDirectory(skillDir, config: lintConfig)
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

    private func loadReplayMap() -> [String: Bool] {
        guard let path = replayMap, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
        return (try? JSONDecoder().decode([String: Bool].self, from: data)) ?? [:]
    }

    // MARK: - spend gate

    /// Confirm spend above the threshold (design P9). `--yes` proceeds; on a TTY we prompt; otherwise
    /// (or `--no-input`, or a declined prompt) we refuse with a usage error carrying the estimate (exit 2).
    private func confirmSpend(trials: Int, limit: Int, skill: String) throws {
        guard trials > limit, !yes else { return }
        let estimate = "\(trials) trials for \(skill) exceeds confirm_above_trials=\(limit)"
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
    private func writeRecords(outcome: Runner.Outcome, skillDir: URL, harness: String, k: Int, judge: SkilletConfig.Judge, base: URL) throws {
        let evalDir = skillDir.appendingPathComponent("evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(BenchmarkFile(report: outcome.report, evals: outcome.evals, harness: harness, k: k, judge: judge))
            .write(to: evalDir.appendingPathComponent("benchmark.json"))
        try encoder.encode(GradingFile(evals: outcome.evals))
            .write(to: evalDir.appendingPathComponent("grading.json"))
        if let runJSON = try? SkilletJSON.encode(outcome.report) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try? Data(runJSON.utf8).write(to: base.appendingPathComponent("run.json"))
        }
    }

    /// Onboarding: after a run, the human commits the records (P5); later loop verbs land in Phase 2.
    static func nextSteps() -> [String] {
        let registered = Set(SkilletCommand.configuration.subcommands.compactMap { $0.configuration.commandName })
        let verbs = ["next", "iterate"].filter { registered.contains($0) }.map { "skillet \($0)" }
        return verbs.isEmpty ? ["commit evaluations/benchmark.json + grading.json"] : verbs
    }
}
