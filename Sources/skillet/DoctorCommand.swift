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
            for skillDir in selected {
                let name = skillDir.lastPathComponent
                // One filesystem audit per skill; every adapter's row reads the same result.
                let audit = SkillBundleAudit.audit(skillDirectory: skillDir)
                for adapter in adapters {
                    rows += Self.visibilityRows(skill: name, audit: audit, adapter: adapter)
                }
                rows += try Self.lintRows(skill: name, directory: skillDir, config: config?.lint ?? .init())
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

    /// The free lint gate as doctor rows: error tier fails (exit 3 here — command-contextual, like
    /// `run`'s exit-2 recolor), warn tier shows without failing.
    static func lintRows(skill: String, directory: URL, config: SkilletConfig.Lint) throws -> [DoctorReport.Row] {
        let report = try lintSkillDirectory(directory, config: config)
        // Presence-guaranteed (review round 2): a clean catalog still emits its row, so a JSON
        // consumer can distinguish "lint passed" from "lint didn't run".
        guard !report.diagnostics.isEmpty else {
            return [.pass(check: DoctorReport.Check.skillLint, subject: skill, message: "no findings (shipped catalog)")]
        }
        return report.diagnostics.map { diagnostic in
            diagnostic.tier == .error
                ? .failure(
                    check: DoctorReport.Check.skillLint,
                    subject: skill,
                    message: "\(diagnostic.id): \(diagnostic.message)",
                    remedy: diagnostic.fixHint
                )
                : .warning(
                    check: DoctorReport.Check.skillLint,
                    subject: skill,
                    message: "\(diagnostic.id): \(diagnostic.message)"
                )
        }
    }

    /// Bounded path list for row messages: first five, then a count.
    private static func list(_ paths: [String]) -> String {
        let shown = paths.prefix(5).joined(separator: ", ")
        return paths.count > 5 ? "\(shown) (+\(paths.count - 5) more)" : shown
    }
}
