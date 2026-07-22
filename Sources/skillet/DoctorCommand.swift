import ArgumentParser
import Foundation
import EDDCore
import ProjectKit
import ConfigYAML
import LintKit
import HarnessKit
import RenderKit

/// `skillet doctor` — the free $0 preflight (design §6.1, P6): config parses (+ which file loaded),
/// each paid-capable harness resolves (binary · version/denylist · auth), every selected skill is
/// *visible* under the injection strategy (§9.2 positive-load half), and the free error-tier lint
/// gate is green — all before any paid run. Frozen contract: exit `0` = no failure rows (warnings
/// never fail), `3` = any failure (each with a remedy line), `2`/`4` = the shared usage/artifact
/// classes. Auth is a *warning* here — `run`'s strict preflight refuses before spending (F7), so
/// doctor stays green in authless environments (CI).
struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Free $0 preflight: config, harness resolution, skill visibility, lint.",
        discussion: """
        Runs every free check a paid run depends on and prints one ✓/!/✗ row per check with a fix \
        line under each failure. Catches the silent killers: a broken config, an unresolvable or \
        denylisted harness binary, a skill bundle the harness would silently see incompletely \
        (symlinked references), and error-tier lint findings. Warnings (e.g. not authenticated) \
        never fail doctor — `skillet run` enforces auth before any spend.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Limit to specific skills by name; defaults to all discovered skills.")
    var skills: [String] = []

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
            guard let root = context.root.map({ URL(fileURLWithPath: $0) }) else {
                throw EDDError.projectNotFound(cwd: context.cwd)
            }

            // Config: strict load (shared classes: missing --config → 2, undecodable → 4) + origin.
            let (config, origin) = try loadConfigWithOrigin(options: options, context: context)
            var rows: [DoctorReport.Row] = [
                .pass(check: DoctorReport.Check.config, message: origin.human)
            ]

            let skillsRoot = config?.project?.skillsRoot ?? "skills"
            let discovered = SkillScanner().scan(skillsRoot: root.appendingPathComponent(skillsRoot))
            let selected = try selectSkillDirectories(discovered, requested: skills, command: "doctor")

            // The paid-capable adapters. The replay double is a test seam — it preflights nothing,
            // so doctor doesn't row it (it would always trivially pass).
            let adapters: [any HarnessAdapter] = [ClaudeCodeAdapter(configPath: config?.harness?.claudeCode?.path)]

            for adapter in adapters {
                rows += await Self.harnessRows(for: adapter)
            }
            // Capture's secret scanner (F32): a warning if betterleaks is unresolved, so its absence is
            // known before a capture would fail closed at runtime — never a failure (redaction guards the write).
            rows.append(await Self.secretScannerRow(config: config))
            for skillDir in selected {
                let name = skillDir.lastPathComponent
                // One filesystem audit per skill; every adapter's row reads the same result.
                let audit = SkillBundleAudit.audit(skillDirectory: skillDir)
                for adapter in adapters {
                    rows += Self.visibilityRows(skill: name, audit: audit, adapter: adapter)
                }
                rows.append(Self.triggerEvalsRow(skill: name, directory: skillDir))
                do {
                    rows += try Self.lintRows(skill: name, directory: skillDir, config: config?.lint ?? .init())
                } catch let error as EDDError {
                    // One-pass doctor (this command's own contract: never fix-one-rerun-discover-next):
                    // a refused lint-input read — a symlinked/special/hard-linked SKILL.md under the F33
                    // safe-read guards — becomes a failure ROW beside the visibility findings, not a
                    // whole-command abort that would hide every other check.
                    rows.append(.failure(check: DoctorReport.Check.skillLint, subject: name,
                                         message: error.message, remedy: error.remedy))
                }
            }

            let report = DoctorReport(rows: rows)
            // Zero skills with a healthy project means init already ran — suggest authoring, not init.
            let nextSteps = report.healthy
                ? [selected.first.map { "skillet run \($0.lastPathComponent)" }
                    ?? "add a skill under \(skillsRoot)/<name>/ (SKILL.md + evaluations/evals.json), then re-run skillet doctor"]
                : []
            Console.emit(try renderer.renderDoctor(report, nextSteps: nextSteps))
            if !report.healthy {
                throw SilentExit(code: report.exitCode.rawValue)
            }
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }

    /// The `capture.secret-scanner` preflight (F32): resolve `betterleaks` the way `capture` does
    /// (env `SKILLET_BETTERLEAKS_BIN` › `sanitize.scanner_path` › `PATH`; doctor has no
    /// `--secret-scanner-path` flag) and, when resolved, probe its version. A **warning** when absent —
    /// `capture` fails closed at runtime, so early absence is informational, never a doctor failure.
    static func secretScannerRow(
        config: SkilletConfig?,
        resolver: BinaryResolver = BinaryResolver(),
        launcher: any ProcessLauncher = SubprocessLauncher()
    ) async -> DoctorReport.Row {
        guard let resolved = resolver.resolve(
            flag: nil, envVar: "SKILLET_BETTERLEAKS_BIN",
            configPath: config?.sanitize?.scannerPath, pathName: "betterleaks")
        else {
            return .warning(
                check: DoctorReport.Check.secretScanner,
                message: "betterleaks not found on env, config, or PATH — capture fails closed (it never writes an unscrubbed bundle)",
                remedy: "install betterleaks, or set SKILLET_BETTERLEAKS_BIN or sanitize.scanner_path")
        }
        // A resolved path is not proof the binary *works*: an env/config override can point at a missing
        // or broken file. Probe its version — if that fails, the scanner won't run, so warn (don't pass a
        // capture that would fail closed). Only a binary that answers `version` is a green row.
        guard let version = await Self.betterleaksVersion(resolved.path, launcher: launcher) else {
            return .warning(
                check: DoctorReport.Check.secretScanner,
                subject: "betterleaks",
                message: "betterleaks at \(resolved.path) (via \(resolved.source.rawValue)) did not run — capture would fail closed",
                remedy: "check the binary exists and is executable, or fix SKILLET_BETTERLEAKS_BIN / sanitize.scanner_path")
        }
        return .pass(
            check: DoctorReport.Check.secretScanner,
            subject: "betterleaks",
            message: "\(resolved.path) (via \(resolved.source.rawValue)) — \(version)")
    }

    private static func betterleaksVersion(_ path: String, launcher: any ProcessLauncher) async -> String? {
        guard let out = try? await launcher.run(path, ["version"], workingDirectory: nil,
                                                timeout: .seconds(10), environment: nil, outputLimitBytes: nil),
              out.exitCode == 0 else { return nil }
        let v = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// Binary/version/auth rows from one non-strict probe. Probe *throws* only for hard stops
    /// (unresolvable binary, pinned-banned) — those become failure rows; an auto-discovered banned
    /// version comes back as `bannedVersion` (a failure row too: `run` will refuse it), and a missing
    /// credential is the one warning-tier finding (run's strict preflight owns the refusal).
    static func harnessRows(for adapter: any HarnessAdapter) async -> [DoctorReport.Row] {
        let harness = adapter.id.rawValue
        do {
            let info = try await adapter.probe(strict: false)
            var rows: [DoctorReport.Row] = [
                .pass(
                    check: DoctorReport.Check.harnessBinary,
                    subject: harness,
                    message: "\(info.binaryPath ?? "resolved") (via \(info.source ?? "?"))"
                )
            ]
            if let banned = info.bannedVersion {
                rows.append(.failure(
                    check: DoctorReport.Check.harnessVersion,
                    subject: harness,
                    message: "version \(banned) is on the known-bad denylist — `skillet run` will refuse it",
                    remedy: "pin a non-banned version, or set SKILLET_ALLOW_BANNED_\(harness.uppercased().replacingOccurrences(of: "-", with: "_"))=1 to override deliberately"
                ))
            } else {
                rows.append(.pass(
                    check: DoctorReport.Check.harnessVersion,
                    subject: harness,
                    message: info.version
                ))
            }
            if info.authenticated {
                rows.append(.pass(
                    check: DoctorReport.Check.harnessAuth,
                    subject: harness,
                    message: "authenticated"
                ))
            } else {
                rows.append(.warning(
                    check: DoctorReport.Check.harnessAuth,
                    subject: harness,
                    message: "not authenticated — `skillet run` will refuse before spending",
                    remedy: EDDError.harnessUnauthenticated(harness: harness).remedy
                ))
            }
            return rows
        } catch let error as EDDError {
            let check: String
            switch error {
            case .harnessBanned: check = DoctorReport.Check.harnessVersion
            default: check = DoctorReport.Check.harnessBinary
            }
            return [.failure(check: check, subject: harness, message: error.message, remedy: error.remedy)]
        } catch {
            return [.failure(
                check: DoctorReport.Check.harnessBinary,
                subject: harness,
                message: "probe failed: \(error)",
                remedy: "install \(harness), or pin its path (SKILLET_\(harness.uppercased().replacing("-", with: "_"))_BIN / harness.\(harness).path), then re-run"
            )]
        }
    }

    /// The §9.2 positive-load rows for one skill×harness pair, from the (per-skill, pre-computed)
    /// staging-parity audit: a symlink staging would silently drop is a failure (incomplete
    /// model-visible bundle); hidden entries dropped by policy are a warning. When both a SKILL.md
    /// issue and dropped symlinks exist, one failure row reports both — doctor's job is the whole
    /// preflight in one pass, never fix-one-rerun-discover-next.
    static func visibilityRows(skill: String, audit: SkillBundleAudit.Result, adapter: any HarnessAdapter) -> [DoctorReport.Row] {
        let subject = "\(skill) (\(adapter.id.rawValue))"
        var rows: [DoctorReport.Row] = []
        if audit.isVisible {
            rows.append(.pass(
                check: DoctorReport.Check.skillVisibility,
                subject: subject,
                message: "SKILL.md + bundle stage completely under the injection strategy"
            ))
        } else {
            var problems: [String] = []
            var remedies: [String] = []
            if let issue = audit.skillMDIssue {
                problems.append(issue)
                remedies.append(EDDError.skillNotVisible(skill: skill, reason: issue).remedy)
            }
            if !audit.symlinks.isEmpty {
                problems.append("staging silently drops symlinked bundle entries: \(list(audit.symlinks))")
                remedies.append("replace symlinked bundle entries with regular files — staging drops symlinks, so the harness would see an incomplete bundle")
            }
            rows.append(.failure(
                check: DoctorReport.Check.skillVisibility,
                subject: subject,
                message: problems.joined(separator: "; "),
                remedy: remedies.joined(separator: "; ")
            ))
        }
        if !audit.droppedHidden.isEmpty {
            rows.append(.warning(
                check: DoctorReport.Check.skillVisibility,
                subject: subject,
                message: "staging drops hidden entries: \(list(audit.droppedHidden))"
            ))
        }
        return rows
    }

    /// The trigger-test file's own health row (review round 4: with valid behavioral evals there is
    /// no L009 finding to hang trigger-file problems on, so a rotten file was invisible here while
    /// default `run` refused it). Presence-guaranteed like every check; severities mirror exactly
    /// what the runner does — via the same SHARED checker it uses.
    static func triggerEvalsRow(skill: String, directory: URL) -> DoctorReport.Row {
        switch loadTriggerEvals(skillDir: directory) {
        case .absent:
            return .pass(check: DoctorReport.Check.skillTriggerEvals, subject: skill,
                         message: "no trigger-eval.json (trigger axis not configured)")
        case .usable(let cases):
            return .pass(check: DoctorReport.Check.skillTriggerEvals, subject: skill,
                         message: "\(cases.count) case(s)")
        case .empty:
            return .warning(check: DoctorReport.Check.skillTriggerEvals, subject: skill,
                            message: "trigger-eval.json has no cases — the trigger axis will be skipped",
                            remedy: "add {query, should_trigger} cases to evaluations/trigger-eval.json")
        case .invalid(let reason):
            return .failure(check: DoctorReport.Check.skillTriggerEvals, subject: skill,
                            message: "trigger-eval.json: \(reason) — `skillet run` will refuse it",
                            remedy: "fix evaluations/trigger-eval.json (a JSON array of {query, should_trigger} objects)")
        }
    }

    /// The free lint gate as doctor rows: error tier fails (exit 3 here — command-contextual, like
    /// `run`'s exit-2 recolor), warn tier shows without failing.
    static func lintRows(skill: String, directory: URL, config: SkilletConfig.Lint) throws -> [DoctorReport.Row] {
        let report = try lintSkillDirectory(directory, config: config)
        // Presence-guaranteed (review round 2): a clean catalog still emits its row, so a JSON
        // consumer can distinguish "lint passed" from "lint didn't run".
        guard !report.diagnostics.isEmpty else {
            return [.pass(check: DoctorReport.Check.skillLint, subject: skill, message: "no findings (shipped catalog)")]
        }
        // Doctor predicts the runner (P6). Since F14, `run` accepts a trigger-only skill — so the
        // has-evals error softens to a warning ONLY when BOTH hold (review round 3): the trigger
        // file is usable per the SHARED checker (the very judgment `run` uses — symlink-guarded, so
        // the two commands cannot drift), and evals.json is genuinely ABSENT. If evals.json exists
        // in any state, `run --axis all` will try to load it and refuse a corrupt one (exit 4), so
        // the failure must stand — the lint message already says "exists but is not valid JSON".
        let triggerEvals = loadTriggerEvals(skillDir: directory)
        let triggerUsable = { if case .usable = triggerEvals { return true } else { return false } }()
        let triggerPresentUnusable = {
            switch triggerEvals {
            case .empty, .invalid: return true
            case .absent, .usable: return false
            }
        }()
        // "Absent" means NO ENTRY AT ALL: a dangling symlink answers false to the follow-the-link
        // exists check, but the entry is there and `run` refuses it before any axis (round 6 —
        // symlink check before exists check, always).
        let evalsURL = directory.appendingPathComponent("evaluations/evals.json")
        let evalsAbsent = !SkillBundleRules.isSymlink(evalsURL)
            && !FileManager.default.fileExists(atPath: evalsURL.path)
        return report.diagnostics.map { diagnostic in
            if diagnostic.tier == .error && !(triggerUsable && evalsAbsent && diagnostic.id == "SKILL-L009") {
                var message = "\(diagnostic.id): \(diagnostic.message)"
                var remedy = diagnostic.fixHint
                if diagnostic.id == "SKILL-L009" && triggerPresentUnusable {
                    message += " — trigger-eval.json is present but invalid, empty, or symlinked"
                    remedy += "; or fix evaluations/trigger-eval.json so the trigger axis can run"
                }
                return .failure(check: DoctorReport.Check.skillLint, subject: skill, message: message, remedy: remedy)
            }
            return .warning(
                check: DoctorReport.Check.skillLint,
                subject: skill,
                message: "\(diagnostic.id): \(diagnostic.message)",
                remedy: diagnostic.tier == .error ? diagnostic.fixHint : nil
            )
        }
    }

    /// Bounded path list for row messages: first five, then a count.
    private static func list(_ paths: [String]) -> String {
        let shown = paths.prefix(5).joined(separator: ", ")
        return paths.count > 5 ? "\(shown) (+\(paths.count - 5) more)" : shown
    }
}
