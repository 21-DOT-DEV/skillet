import ArgumentParser
import Foundation
import EDDCore
import AnalysisKit
import ConfigYAML
import ProjectKit
import RenderKit

/// `skillet triage` — the Interpret step (design §6.1, F33 Track A): free error analysis across the
/// captured session corpus. Clusters each bundle's **cached** scorer findings by rule (Specs/016 D1/D2),
/// writes each new cluster as a `skillet.finding/1` evidence file routed to its cheapest lever
/// (a hypothesis, not a verdict — D4), and joins findings to friction events via shared sessions (D6).
/// A **reporter, not a gate**: exit 0 even with clusters. Re-runs only add missing findings — an
/// existing file is never modified, a human-closed cluster is never auto-reopened (D3).
struct TriageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "triage",
        abstract: "Free error analysis: cluster cached scorer findings across the session corpus into routed finding files.",
        discussion: """
        Reads each captured session bundle's cached scorer results (no re-scoring, no model, no \
        network), clusters hits by rule into a ranked failure taxonomy, and writes one finding file \
        per new cluster under evaluations/<skill>/findings/ — durable evidence the gates engine will \
        consume. Findings auto-link to friction events that share sessions. Re-runs never modify an \
        existing finding: a still-firing cluster whose finding you closed is reported, not reopened. \
        Use --dry-run to preview without writing.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Limit to specific skills by name; defaults to all discovered skills.")
    var skills: [String] = []

    @Option(name: .long, help: "Only include recordings dated YYYY-MM-DD or later (by bundle stem).")
    var since: String?

    @Flag(name: .long, help: "Preview the taxonomy and would-be finding files without writing.")
    var dryRun = false

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            if let since, !Self.isValidDate(since) {
                throw EDDError.usage(message: "invalid --since '\(since)'", remedy: "use YYYY-MM-DD")
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
            guard let root = context.root.map({ URL(fileURLWithPath: $0) }) else {
                throw EDDError.projectNotFound(cwd: context.cwd)
            }
            let config = try loadConfig(options: options, context: context)
            let skillsRoot = config?.project?.skillsRoot ?? "skills"
            let discovered = SkillScanner().scan(skillsRoot: root.appendingPathComponent(skillsRoot))
            let selected = try selectSkillDirectories(discovered, requested: skills, command: "triage")

            let runDate = Self.dateStamp(now: Date())
            var skillReports: [SkillTriage] = []
            for skillDir in selected {
                skillReports.append(try triageSkill(
                    skillDir, projectRoot: root, skillsRoot: skillsRoot, runDate: runDate))
            }
            let report = TriageReport(skills: skillReports, dryRun: dryRun)
            let allEmpty = skillReports.allSatisfy { $0.totalRecordings == 0 }
            // Footer targets the skill with something to act on (round 12 — `selected.first` pointed
            // the suggestion at whichever skill sorted first, even when a later one produced the
            // results): first with clusters, else first with recordings, else first selected (the
            // all-empty case, where the capture suggestion fits any of them equally).
            let footerSkill = (skillReports.first { !$0.clusters.isEmpty }
                ?? skillReports.first { $0.totalRecordings > 0 }
                ?? skillReports.first)?.skill
            Console.emit(try renderer.renderTriage(
                report, nextSteps: Self.nextSteps(
                    emptyCorpus: allEmpty, skill: footerSkill, skillsRoot: skillsRoot, since: since)))
            // Reporter: no non-zero exit on clusters/disclosures.
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }

    // MARK: - Per-skill orchestration (shell: loader → evidence decode → pure engine → writes)

    private func triageSkill(_ skillDir: URL, projectRoot: URL, skillsRoot: String, runDate: String) throws -> SkillTriage {
        let skill = skillDir.lastPathComponent
        // Confinement first (review round 2, SECURITY — the guard `run`/`capture` already apply): a
        // symlinked `evaluations`/`sessions`/`findings`/`friction` component could read bundles from —
        // and create finding files in — an arbitrary directory outside the project. **Rebuild the skill
        // path lexically under the project root** (capture's pattern) rather than guarding the scanner's
        // URL: `contentsOfDirectory` returns realpath-resolved URLs (`/var` → `/private/var` on Darwin)
        // while the locator's root is lexical, and `standardizedFileURL` strips `/private` only for
        // paths that *exist* — so a mixed pair makes the confinement prefix test unsound for
        // not-yet-existing components (`findings/` before the first write). One canonical space by
        // construction; every read and write below uses the vetted path (CWE-59/CWE-22: lstat the
        // unresolved components, treat not-confined as blocked — `firstSymlinkOnPath`'s contract).
        let confinedSkillDir = projectRoot.appendingPathComponent(skillsRoot).appendingPathComponent(skill)
        try Self.assertConfined(skillDir: confinedSkillDir, projectRoot: projectRoot, skill: skill)
        let evalDir = confinedSkillDir.appendingPathComponent("evaluations")
        let findingsDir = evalDir.appendingPathComponent("findings")
        var disclosures: [DisclosedInput] = []

        // A regular file where a directory belongs (round 15, finding 2): the loaders would read it as
        // "nothing here" and the command would print "no recordings — capture one" — the fail-fast
        // literature's "doomed to fail later" red herring. It's a *certain* corpus-integrity problem, so
        // surface it specifically (what / where / how-to-fix); the command still notes-and-continues
        // (reporter posture — exit 0; the exit-code policy for integrity problems is tracked, Specs/017 T12).
        for (label, dir) in [("evaluations", evalDir),
                             ("evaluations/sessions", evalDir.appendingPathComponent("sessions")),
                             ("evaluations/findings", findingsDir),
                             ("evaluations/friction", evalDir.appendingPathComponent("friction"))] {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), !isDir.boolValue {
                disclosures.append(DisclosedInput(
                    subject: "\(skill)/\(label)",
                    reason: "is a file, not a directory (a folder was expected here) — remove or rename it"))
            }
        }

        let (bundles, loaderDisclosures) = CorpusLoader().load(
            sessionsDir: evalDir.appendingPathComponent("sessions"), since: since)
        disclosures += loaderDisclosures
        // `map`, not `compactMap` (round 3): every evidence file yields a ref — a non-Finding (e.g. a
        // misplaced friction event) just carries a nil cluster, so it can never match a slug.
        let existing = Self.scanEvidence(findingsDir, into: &disclosures).map {
            ExistingFindingRef(id: $0.header.id, cluster: ($0 as? Finding)?.cluster, state: $0.header.state)
        }
        let friction = Self.scanEvidence(evalDir.appendingPathComponent("friction"), into: &disclosures)
            .map { FrictionRef(id: $0.header.id, sessions: $0.header.sessions) }

        let result = TriageEngine.triage(
            skill: skill, runDate: runDate, runningVersion: SkilletVersion.current,
            bundles: bundles, disclosures: disclosures,
            existingFindings: existing, friction: friction)

        // Writes (D3: create-missing only; A5 collision safety: never overwrite an unexpected file).
        // Each would-be-`new` cluster is finalized to its REAL outcome (round 15, Unknown 1=B):
        // written / blocked-exists / write-failed, so the table AND the machine payload say what
        // happened — no "blocked because a file exists" lie over a write error.
        var written: [String] = []
        var writeDisclosures: [DisclosedInput] = []
        var outcomes: [String: String] = [:]   // findingId → finalized fileStatus
        if !dryRun {
            var dirReady = true
            if !result.newFindings.isEmpty {
                do {
                    // Surface a create-directory failure ONCE (round 15, finding 1a — the old `try?`
                    // swallowed it and let every per-finding write fail separately). If the dir can't be
                    // made (a file blocks it, permissions), all pending findings are write-failed.
                    try FileManager.default.createDirectory(at: findingsDir, withIntermediateDirectories: true)
                } catch {
                    dirReady = false
                    writeDisclosures.append(DisclosedInput(
                        subject: "\(skill)/evaluations/findings",
                        reason: "could not create the findings directory — no new findings written: \(error)"))
                }
            }
            for newFinding in result.newFindings {
                let id = newFinding.finding.header.id
                let name = "\(id).md"
                let dest = findingsDir.appendingPathComponent(name)
                guard dirReady else { outcomes[id] = "write-failed"; continue }
                if FileManager.default.fileExists(atPath: dest.path) || SafeFile.isSymlink(dest) {
                    // `cluster` is `String?` on the F29 record; engine-synthesized findings always carry
                    // one, so the fallback is unreachable — but never interpolate an Optional (round 3).
                    outcomes[id] = "blocked-exists"
                    writeDisclosures.append(DisclosedInput(
                        subject: "findings/\(name)",
                        reason: "a file already exists at findings/\(name) — the '\(newFinding.finding.cluster ?? "?")' finding was not written (remove it if unrelated)"))
                    continue
                }
                do {
                    let text = try EvidenceFrontmatter.encode(newFinding.finding, body: newFinding.body)
                    try Data(text.utf8).write(to: dest, options: [.withoutOverwriting])
                    written.append("findings/\(name)")
                    outcomes[id] = "written"
                } catch {
                    outcomes[id] = "write-failed"
                    writeDisclosures.append(DisclosedInput(
                        subject: "findings/\(name)", reason: "write failed: \(error)"))
                }
            }
        }
        // Finalize a would-be-`new` row to its real outcome; `--dry-run` leaves `new` (a preview).
        let clusters = dryRun ? result.clusters : result.clusters.map { row in
            row.fileStatus == "new" ? row.withFileStatus(outcomes[row.findingId] ?? "write-failed") : row
        }

        return SkillTriage(
            skill: skill,
            clusters: clusters,
            staleRecordings: result.staleRecordings,
            totalRecordings: result.totalRecordings,
            unreadableHits: result.unreadableHits,
            disclosures: (result.disclosures + writeDisclosures).map {
                TriageDisclosure(subject: $0.subject, reason: $0.reason)
            },
            written: written)
    }

    /// Refuse a symlinked or project-escaping component on any directory triage reads or writes.
    /// `sessions`/`findings`/`friction` may not exist yet — a missing component lstats as "not a
    /// symlink", so a fresh skill passes untouched.
    static func assertConfined(skillDir: URL, projectRoot: URL, skill: String) throws {
        let evaluations = skillDir.appendingPathComponent("evaluations")
        for target in [skillDir, evaluations,
                       evaluations.appendingPathComponent("sessions"),
                       evaluations.appendingPathComponent("findings"),
                       evaluations.appendingPathComponent("friction")] {
            if let link = SafeFile.firstSymlinkOnPath(from: projectRoot, to: target) {
                throw EDDError.invalidArtifact(
                    path: skill,
                    reason: "triage path crosses a symlink or escapes the project (not allowed): \(link.lastPathComponent)")
            }
        }
    }

    /// Decode every evidence file under `dir` (findings or friction), symlink-guarded; an undecodable
    /// or misnamed file is disclosed and skipped — malformed input is data, never a crash.
    /// Evidence markdown is small (frontmatter + a short body); anything past this is disclosed, not read
    /// — a bound over `boundedRead`, matching `BodyExtractor`'s 1 MiB (round 8).
    static let evidenceSizeCap = 1 << 20

    static func scanEvidence(_ dir: URL, into disclosures: inout [DisclosedInput]) -> [any Evidence] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var out: [any Evidence] = []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            // Hidden entries (`.#foo.md` editor locks etc.) are silently skipped — genuine non-candidates,
            // no signal. A **symlink is surfaced** (round 16), not silently skipped: the surface-every-
            // anomaly posture + a mild escape signal (it could point outside the project) — rsync warns on
            // exactly this by default. The read goes through the one sanctioned untrusted read (F33), whose
            // guard order (symlink → special → hard link → bounded) drives the disclosed reasons below.
            guard name.hasSuffix(".md"), !SafeFile.isHidden(name) else { continue }
            let text: String
            switch SafeFile.readPlainText(url, cap: Self.evidenceSizeCap) {
            case let .success(contents):
                text = contents
            case .failure(.symlink):
                disclosures.append(DisclosedInput(subject: "\(dir.lastPathComponent)/\(name)",
                                                  reason: "is a symbolic link — not followed; its records were not counted (replace it with a regular file)"))
                continue
            case .failure(.notRegularFile), .failure(.hardLink):
                disclosures.append(DisclosedInput(subject: "\(dir.lastPathComponent)/\(name)",
                                                  reason: "not a plain regular file (special file or hard link) — skipped"))
                continue
            case .failure:
                disclosures.append(DisclosedInput(subject: "\(dir.lastPathComponent)/\(name)",
                                                  reason: "unreadable, oversized, or not UTF-8 text — skipped"))
                continue
            }
            do {
                out.append(try EvidenceFrontmatter.decode(text, filename: name).evidence)
            } catch {
                disclosures.append(DisclosedInput(subject: "\(dir.lastPathComponent)/\(name)",
                                                  reason: "undecodable evidence — skipped (fix or remove)"))
            }
        }
        return out
    }

    // MARK: - Next steps (the registration-guarded footer, Specs/016 round 2)

    /// Actionable suggestions name only registered subcommands (AGENTS binding rule). `next` flips in
    /// automatically the day Phase 5 registers it; until then the future command appears only in
    /// once-it-lands prose (capture's `friction add` precedent).
    static func nextSteps(emptyCorpus: Bool, skill: String?, skillsRoot: String, since: String? = nil,
                          registered: Set<String>? = nil) -> [String] {
        let reg = registered ?? Set(SkilletCommand.configuration.subcommands.compactMap { $0.configuration.commandName })
        // No skill discovered (empty tree, or the only candidate was a symlink discovery skips —
        // round 2): a `--skill <skill>` command isn't runnable, so give descriptive guidance ending in
        // a real re-run, exactly as `doctor` does for a skill-less project (round 5 — was leaking the
        // literal `<skill>`/`<slug>` placeholders).
        guard let skill else {
            return ["add a skill (\(skillsRoot)/<name>/SKILL.md), capture a session, then re-run skillet triage"]
        }
        // A known skill with an empty corpus: capture is the next step, but the slug names the session
        // and has no default. Frame it as instruction ("record a session — …"), so the one unavoidable
        // placeholder reads as a fill-in rather than a broken copy-paste command (round 6 — a required
        // arg with no derivable default is shown as a placeholder, mirroring the command's own synopsis).
        if emptyCorpus, reg.contains("capture") {
            // A date filter that hid every recording is not "capture something" (round 16): name the
            // filter so the hint matches reality — accurate whether the corpus is truly empty or filtered.
            if let since {
                return ["no recordings on or after \(since) — widen --since, or record a new session: skillet capture --skill \(skill) --slug <name>"]
            }
            return ["record a session — skillet capture --skill \(skill) --slug <name>"]
        }
        if reg.contains("next") { return ["skillet next"] }
        return ["review findings under evaluations/\(skill)/findings/ — `skillet next` picks them up once it lands (Phase 5)"]
    }

    // MARK: - Date helpers (capture's stamp semantics: UTC, en_US_POSIX)

    static func dateStamp(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }

    /// Syntactic **and** semantic (round 2: the shape check alone accepted `0000-99-99`, which then
    /// lexically matched no stems — a silent-empty-result footgun). Non-lenient parse + round-trip,
    /// so a real-but-overflowed date (`2026-02-30`) can't slip through formatter coercion either.
    static func isValidDate(_ s: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: s) else { return false }
        return formatter.string(from: date) == s
    }
}
