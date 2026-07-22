import ArgumentParser
import Foundation
import EDDCore
import ProjectKit
import RenderKit
import TraceKit
import HarnessKit
import ScoreKit
import CorpusKit
import SanitizerKit

/// `skillet capture` — the Discover step (F26/F32). Turns a just-finished claude-code session into a
/// normalized, **scrubbed**, scored session bundle. Capture always sanitizes and fails closed if the
/// scanner can't run (constitution VI); it is registered only because the real `BetterleaksSanitizer`
/// is wired in (the exposure-gate, R8-C1).
struct CaptureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Record a production session as a scrubbed, scored evidence bundle.",
        discussion: """
        Locates the session (the newest in the workspace by default, or `--session`), normalizes it, renders a transcript, captures the \
        workspace diff + produced bodies, **redacts secrets in place** (betterleaks, resolved), scores \
        the redacted bodies, and writes the frozen bundle under \
        `<skills_root>/<skill>/evaluations/sessions/<date>-<slug>.*`. Never writes an unscrubbed bundle: \
        if the scanner can't run, capture fails closed. `--fail-on-secret` exits 1 for CI when a secret \
        was found (the bundle is written scrubbed either way).
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(help: "The skill this session exercised (its evaluations/sessions/ receives the bundle).")
    var skill: String
    @Option(help: "Kebab-case slug for the bundle filename stem.")
    var slug: String
    @Option(help: "A specific native session (uuid or .jsonl path). Default: the newest session in the workspace.")
    var session: String?
    @Option(help: "Harness id (default claude-code).")
    var harness: String?
    @Option(name: .customLong("target-dir"), help: "The workspace the session ran in (default: current dir).")
    var targetDir: String?
    @Option(help: "Bundle date YYYY-MM-DD (default: today, UTC).")
    var date: String?
    @Flag(help: "Overwrite an existing bundle with the same stem.")
    var force: Bool = false
    @Option(help: "Model id for provenance (default: read from the session log).")
    var model: String?
    @Option(name: .customLong("skill-version"), help: "Skill version for provenance (default: unknown).")
    var skillVersion: String?
    @Flag(name: .customLong("fail-on-secret"), help: "Exit 1 (for CI) if any secret was found (still writes the scrubbed bundle).")
    var failOnSecret: Bool = false
    @Option(name: .customLong("secret-scanner-path"), help: "Path to the betterleaks binary (overrides env/config/PATH).")
    var secretScannerPath: String?

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            try await capture()
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }

    private func capture() async throws {
        // Validate identity inputs up front with an **allowlist** (accept only safe characters), not a
        // blocklist — so a bad `--slug`/`--date` can never escape `sessionsDir` (path traversal, log-a)
        // or produce an unsortable stem. Ported from the predecessor's validation.
        guard Self.isValidSlug(slug) else {
            throw EDDError.usage(message: "invalid --slug '\(slug)'",
                                 remedy: "use lowercase kebab-case matching ^[a-z0-9][a-z0-9-]*$ (no slashes or dots)")
        }
        // `--skill` becomes a directory component of `sessionsDir`; validate it as a safe single path
        // component (same kebab-case allowlist) so it can't traverse (`../..`) out of the skills root.
        guard Self.isValidSkillName(skill) else {
            throw EDDError.usage(message: "invalid --skill '\(skill)'",
                                 remedy: "use the skill's directory name — a single path component (no '/', no '..', not empty)")
        }
        if let date, !Self.isValidDate(date) {
            throw EDDError.usage(message: "invalid --date '\(date)'", remedy: "use YYYY-MM-DD")
        }
        // Only claude-code has the sessionCapture capability in v1 (design §9.5); fail loudly for others.
        if let harness, harness != "claude-code" {
            throw EDDError.usage(message: "harness '\(harness)' cannot capture sessions (no native session store)",
                                 remedy: "use --harness claude-code (the only harness with session capture in v1)")
        }
        let launcher = SubprocessLauncher()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
        guard let projectRoot = context.root else { throw EDDError.projectNotFound(cwd: context.cwd) }
        // Resolve the project root + `-C`-aware cwd through symlinks BEFORE deriving the write path or any
        // confinement check: a symlinked project root otherwise passes the lexical guard while the bundle
        // lands on the link's target (finding). `-C` (options.directory) is folded into `context.cwd`; use
        // it — not the raw process cwd — as the base for the workspace, a relative `--target-dir`, and a
        // relative `--session` path. `resolvingSymlinksInPath` is a no-op for ordinary real paths.
        // Treat both roots as directories so relative `--target-dir` / `--session` paths append to them,
        // not to their last path component (Foundation `URL(fileURLWithPath:relativeTo:)` treats a
        // non-directory base as a file, so `subdir` against `/tmp` resolves to `/subdir`).
        let projectRootURL = URL(fileURLWithPath: projectRoot, isDirectory: true).resolvingSymlinksInPath()
        let base = URL(fileURLWithPath: context.cwd, isDirectory: true).resolvingSymlinksInPath()
        let config = try loadConfig(options: options, context: context)
        let skillsRoot = config?.project?.skillsRoot ?? "skills"
        let sessionsDir = projectRootURL
            .appendingPathComponent(skillsRoot).appendingPathComponent(skill)
            .appendingPathComponent("evaluations").appendingPathComponent("sessions")
        // Defense in depth: even with `--skill` validated, `skills_root` comes from config and could
        // contain `..`; assert the resolved sessions dir stays under the project root before we create
        // or write anything (OWASP: canonicalize, then verify the target is confined under the base).
        guard Self.relativePath(of: sessionsDir, under: projectRootURL) != nil else {
            throw EDDError.usage(
                message: "refusing to write outside the project: '\(sessionsDir.standardizedFileURL.path)' escapes '\(projectRootURL.path)'",
                remedy: "remove '..' from skills_root in skillet.yaml and from --skill")
        }
        // The lexical guard above resolves `..` but not **symlinks**: a `skills/<skill>/evaluations`
        // symlink could still redirect `createDirectory`/`write` outside the project. Walk the real
        // filesystem and refuse any symlinked component on the write path (the same guard `run` applies
        // to a skill's own I/O — OWASP: resolve the real path before writing).
        if let link = SafeFile.firstSymlinkOnPath(from: projectRootURL, to: sessionsDir) {
            throw EDDError.usage(
                message: "refusing to write through a symlink on the sessions path: '\(link.path)'",
                remedy: "the bundle destination (\(skillsRoot)/\(skill)/evaluations/sessions) must not cross a symlink")
        }
        // Resolve `--target-dir` through symlinks (consistent with base/projectRoot) AND confine it under
        // the project root: `extractBodies`'s `noSymlink` only guards the *leaf* under `workspace`, not
        // whether `workspace` itself escaped — so a symlinked or absolute `--target-dir` (e.g. `/etc`,
        // `../other`) could make `git diff` + body reads range outside the project. The default (`base`) is
        // always under projectRoot, so this only rejects an explicit escape.
        let workspace = (targetDir.map { URL(fileURLWithPath: $0, relativeTo: base) } ?? base).resolvingSymlinksInPath()
        guard SafeFile.firstSymlinkOnPath(from: projectRootURL, to: workspace) == nil else {
            throw EDDError.usage(
                message: "--target-dir must be inside the project: '\(workspace.path)' escapes '\(projectRootURL.path)' or crosses a symlink",
                remedy: "point --target-dir at the session's workspace within the project (default: the current dir)")
        }

        // 1. Locate + export + normalize.
        let adapter = ClaudeCodeAdapter(launcher: launcher)
        let ref = try await resolveSession(adapter: adapter, workspace: workspace, base: base, projectRoot: projectRootURL)
        let raw: RawTrace
        do { raw = try await adapter.exportSession(ref) }
        catch let HarnessError.executionFailed(_, _, stderr) {
            // The session was FOUND but couldn't be exported (too large, not UTF-8, a symlink/special/hard
            // link, …). Preserve the adapter's reason as an artifact error — don't mislead with "no session
            // found", whose remedy tells the user to re-run or check --target-dir.
            throw EDDError.invalidArtifact(path: ref.path, reason: stderr)
        }
        catch { throw EDDError.invalidArtifact(path: ref.path, reason: "\(error)") }
        let trace = try adapter.parseTrace(raw)

        // 2. Assemble the artifacts (raw — scrubbed next).
        let transcript = TranscriptRenderer.render(trace)
        // If the sessions dir is *inside* the workspace (capturing a session that ran in the skills repo
        // itself), exclude that whole prefix so prior bundle files aren't re-captured into the new one (fix 5).
        let excludePrefix = Self.relativePath(of: sessionsDir, under: workspace)
        let gitPath = BinaryResolver().resolve(flag: nil, envVar: "SKILLET_GIT_BIN", configPath: nil, pathName: "git")?.path
        let (diff, touched) = await GitDiffProvider(git: gitPath, launcher: launcher)
            .diff(workspace: workspace, excludePrefix: excludePrefix)
        let bodies = BodyExtractor.extract(touched: touched, workspace: workspace)
        let bundle = BundleText(transcript: transcript, diff: diff, bodies: bodies, trace: trace)

        // 3. Resolve betterleaks + scrub (fail closed if it can't run).
        guard let betterleaks = BinaryResolver().resolve(
            flag: secretScannerPath, envVar: "SKILLET_BETTERLEAKS_BIN",
            configPath: config?.sanitize?.scannerPath, pathName: "betterleaks")?.path
        else {
            throw EDDError.sanitizerNotFound(reason: "betterleaks not found on the scanner path, env, config, or PATH")
        }
        let scanner = BetterleaksScanner(binaryPath: betterleaks, launcher: launcher)
        // Validate the scanner is a REAL, working secret detector before trusting it — a planted-secret
        // self-test. Without this, `SKILLET_BETTERLEAKS_BIN=/usr/bin/true` (any exit-0 binary) would be
        // treated as a clean scan and an unscrubbed bundle written (CRITICAL). Fail closed if it can't
        // prove itself.
        do { try await scanner.verify() }
        catch { throw EDDError.sanitizerNotFound(reason: "betterleaks self-test failed at \(betterleaks): \(error)") }
        let version = await betterleaksVersion(betterleaks, launcher: launcher)
        let sanitizer = BetterleaksSanitizer(
            scanner: scanner, exemptPaths: Set(config?.sanitize?.exemptPaths ?? []), version: version)
        let (redacted, report): (BundleText, SanitizationReport)
        do { (redacted, report) = try await sanitizer.sanitize(bundle) }
        catch let SanitizerError.exemptPatternTooBroad(pattern) {
            throw EDDError.usage(
                message: "sanitize.exempt_paths pattern '\(pattern)' would exempt every artifact (a blanket bypass)",
                remedy: "use a surgical path or glob (e.g. fixtures/*.md); capture always redacts — there is no --no-sanitize")
        }
        catch let SanitizerError.exemptCoversSyntheticArtifact(artifact) {
            throw EDDError.usage(
                message: "sanitize.exempt_paths must not exempt the core artifact '\(artifact)' — that would disable scanning of a scrubbed surface",
                remedy: "exempt only your own body-file paths; silence a value-level false positive via betterleaks' own allowlist (.betterleaks.toml)")
        }
        catch let e as SanitizerError { throw EDDError.sanitizerNotFound(reason: "\(e)") }

        // 4. Score the redacted bodies (staged so SARIF URIs are bundle-relative), then write. Stamp the
        // whole bundle from ONE clock read so the id, the file stem, and captured_at can never disagree
        // (a midnight crossing between separate Date() reads would otherwise split them across two days).
        let now = Date()
        let stampDate = dateStamp(now: now)
        let sarif = try scoreStaged(redacted.bodies, scorers: config?.scorers ?? .init())
        let meta = SessionMeta.resolve(
            id: "\(stampDate)-\(slug)", skill: skill, harness: harness ?? "claude-code",
            model: model ?? modelFromJSONL(raw.raw), skillVersion: skillVersion, capturedAt: capturedAtStamp(now: now))
        let artifacts: SessionBundleWriter.Artifacts
        do {
            artifacts = try SessionBundleWriter.write(
                redacted, sarif: sarif, sanitization: report, meta: meta,
                into: sessionsDir, date: stampDate, slug: slug, force: force)
        } catch let CorpusError.destinationExists(paths) {
            throw EDDError.captureDestinationExists(paths: paths)
        } catch let CorpusError.writeFailed(path, reason) {
            throw EDDError.invalidArtifact(path: path, reason: reason)
        }

        // 5. Report (honors --json) + corrective nudge; --fail-on-secret is exit 1 (post-write).
        let corrective = CorrectiveTurns.detect(in: trace)
        emitResult(artifacts, report: report, corrective: corrective)
        if failOnSecret, (report.redactions ?? 0) > 0 {
            throw SilentExit(code: ExitCode.measuredFailure.rawValue)   // rotation alarm; bundle already scrubbed
        }
    }

    // MARK: - Session resolution

    private func resolveSession(adapter: ClaudeCodeAdapter, workspace: URL, base: URL, projectRoot: URL) async throws -> NativeSessionRef {
        if let session {
            // Treat `--session` as a file path when it looks like one — a `.jsonl` suffix (even a bare
            // `abc.jsonl`, no slash) or any embedded slash. A relative path resolves against `base`
            // (the `-C`-aware cwd), not the raw process cwd. Only a bare identifier falls through to a
            // UUID lookup in the native store (help: "uuid or .jsonl path").
            if session.hasSuffix(".jsonl") || session.contains("/") {
                let url = URL(fileURLWithPath: session, relativeTo: base).standardizedFileURL
                // Confine a user-supplied session *path* to the project — `--session ../x.jsonl` or an
                // absolute `/etc/….jsonl` must not read outside it, and it must not cross a symlink. (A
                // session in claude's own store is reachable via `--session <uuid>` — or by omitting
                // `--session` for the newest — which use the trusted store lookup below, not this path branch.)
                guard SafeFile.firstSymlinkOnPath(from: projectRoot, to: url) == nil else {
                    throw EDDError.usage(
                        message: "--session path escapes the project or crosses a symlink: '\(url.path)'",
                        remedy: "point --session at a .jsonl inside the project, or use --session <uuid> (or omit it for the newest) for a session in claude's store")
                }
                return NativeSessionRef(id: url.deletingPathExtension().lastPathComponent, path: url.path)
            }
            let matches = try await adapter.locateSessions(SessionQuery(workspace: workspace))
            guard let m = matches.first(where: { $0.id == session }) else {
                throw EDDError.sessionNotFound(workspace: workspace.path)
            }
            return m
        }
        let sessions = try await adapter.locateSessions(SessionQuery(workspace: workspace))
        guard let newest = sessions.first else { throw EDDError.sessionNotFound(workspace: workspace.path) }
        return newest
    }

    // MARK: - Helpers

    private func scoreStaged(_ bodies: [String: String], scorers: SkilletConfig.Scorers) throws -> SarifDocument {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-capture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }   // cleanup is best-effort
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            for (path, text) in bodies {
                let dest = tmp.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: dest)
            }
        } catch {
            // A staging failure would otherwise yield an incomplete SARIF + a successful exit — surface it (fix 6).
            throw EDDError.invalidArtifact(path: "audit-input.sarif (body staging)", reason: "\(error)")
        }
        return ScoreRunner(toolVersion: SkilletVersion.current).run(path: tmp, config: scorers).sarif
    }

    private func betterleaksVersion(_ path: String, launcher: any ProcessLauncher) async -> String? {
        guard let out = try? await launcher.run(path, ["version"], workingDirectory: nil,
                                                timeout: .seconds(10), environment: nil, outputLimitBytes: nil),
              out.exitCode == 0 else { return nil }
        let v = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// Best-effort model for provenance, read from the session JSONL. Parse each line as JSON (not a
    /// literal `"model":"` substring, which breaks the moment an emitter puts a space after the colon —
    /// `"model": "…"`) and take `message.model` (where claude-code stores it) or a top-level `model`.
    private func modelFromJSONL(_ raw: String) -> String? {
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            let value = ((object["message"] as? [String: Any])?["model"] as? String) ?? (object["model"] as? String)
            if let value, !value.isEmpty, value != "<synthetic>" { return value }
        }
        return nil
    }

    /// Machine-readable capture result (`skillet.capture/1`) — the `--json` payload (house snake_case;
    /// the `schema` field is injected by `SkilletJSON`'s envelope).
    private struct CaptureResult: SchemaIdentified {
        static let schema = "skillet.capture/1"
        let bundleStem: String
        let files: [String]
        let redactions: Int
        let scanner: String
        let correctiveTurns: Int
    }

    private func emitResult(_ artifacts: SessionBundleWriter.Artifacts, report: SanitizationReport, corrective: [CorrectiveTurn]) {
        if options.json {
            let result = CaptureResult(
                bundleStem: artifacts.bundleStem, files: artifacts.written.map(\.lastPathComponent).sorted(),
                redactions: report.redactions ?? 0, scanner: report.scanner, correctiveTurns: corrective.count)
            Console.emit(Rendering(stdout: ((try? SkilletJSON.encode(result)) ?? "{}") + "\n"))
        } else {
            Console.emit(Rendering(stdout: textSummary(artifacts, report: report, corrective: corrective)))
        }
    }

    private func textSummary(_ artifacts: SessionBundleWriter.Artifacts, report: SanitizationReport, corrective: [CorrectiveTurn]) -> String {
        var lines = ["captured \(artifacts.bundleStem).* (\(artifacts.written.count) files, \(report.redactions ?? 0) redactions)"]
        let registered = Set(SkilletCommand.configuration.subcommands.compactMap { $0.configuration.commandName })
        // F33: the captured bundle is triage's raw material — suggest the Interpret step (guarded).
        if registered.contains("triage") {
            lines.append("→ mine the corpus for recurring failures: skillet triage \(skill)")
        }
        if !corrective.isEmpty {
            if registered.contains("friction") {
                lines.append("→ looks like you hand-fixed something: skillet friction add --skill \(skill) --sessions \(artifacts.bundleStem)")
            } else {
                lines.append("→ \(corrective.count) corrective turn(s) detected — log with `skillet friction add` once it lands (F30)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Validation (allowlist — path-traversal safe; ported from the predecessor)

    static func isValidSlug(_ s: String) -> Bool {
        // Enforce the documented `^[a-z0-9][a-z0-9-]*$` over **Unicode scalars** (code points), not
        // `Character`: Character comparison is lexical over normalized graphemes, so a decomposed
        // `a`+combining mark or other non-ASCII could slip through if Unicode ordering ever placed it in
        // range. Scalar iteration + code-point bounds is an unambiguous ASCII check.
        guard let first = s.unicodeScalars.first, isSlugHead(first) else { return false }
        return s.unicodeScalars.dropFirst().allSatisfy { isSlugHead($0) || $0 == "-" }
    }
    private static func isSlugHead(_ c: Unicode.Scalar) -> Bool { (c >= "a" && c <= "z") || (c >= "0" && c <= "9") }

    /// A skill's directory name only needs to be a **safe single path component** (it becomes one segment
    /// of `sessionsDir`) — reject empty, `.`/`..`, and any `/` or NUL. Deliberately NOT the slug allowlist:
    /// `SkillScanner`/`run` select any directory containing a `SKILL.md` (`MySkill`, `my_skill`, `my.skill`),
    /// so capture must accept those too; the write-path confinement guards the traversal case regardless.
    static func isValidSkillName(_ s: String) -> Bool {
        !s.isEmpty && s != "." && s != ".." && !s.contains("/") && !s.unicodeScalars.contains("\0")
    }

    static func isValidDate(_ s: String) -> Bool {
        let c = Array(s)
        guard c.count == 10 else { return false }
        func digit(_ i: Int) -> Bool { c[i] >= "0" && c[i] <= "9" }
        // Exact `YYYY-MM-DD` shape...
        guard digit(0) && digit(1) && digit(2) && digit(3) && c[4] == "-"
            && digit(5) && digit(6) && c[7] == "-" && digit(8) && digit(9) else { return false }
        // ...AND a real calendar date — the shape check alone lets `2026-99-99` / `2026-02-30` become a
        // bundle stem + id. `isLenient = false` + a POSIX/UTC formatter rejects impossible dates.
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s) != nil
    }

    /// `url`'s path relative to `base`, or `nil` if `url` is not under `base`.
    static func relativePath(of url: URL, under base: URL) -> String? {
        let u = url.standardizedFileURL.path, b = base.standardizedFileURL.path
        let bSlash = b.hasSuffix("/") ? b : b + "/"
        guard u.hasPrefix(bSlash) else { return nil }
        return String(u.dropFirst(bSlash.count))
    }

    /// The bundle date (`--date` override, else `now` in UTC). Takes `now` so the `id`, the file stem, and
    /// `captured_at` all derive from **one** instant — otherwise a midnight crossing between calls could
    /// give `session-meta.json`'s `id` a different day than the filename or `captured_at`.
    private func dateStamp(now: Date) -> String {
        if let date { return date }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: now)
    }
    private func capturedAtStamp(now: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: now)
    }
}
