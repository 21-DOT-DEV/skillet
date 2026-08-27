import Foundation
import EDDCore
import TraceKit
import ProjectKit

/// The claude-code harness adapter. Parses claude-code's native session JSONL → `Trace`, resolves +
/// vets its binary (`probe`), enforces skill-visibility, and (F7) executes a task one-shot. Every path
/// runs through the injected `ProcessLauncher`, so the logic is unit-tested with a fake; the *live*
/// invocation contract (the exact `claude` flags below, auth, real session shape) is exercised only by
/// F7's opt-in env-gated smoke, since claude-code isn't installable in CI.
public struct ClaudeCodeAdapter: HarnessAdapter {
    public let id: HarnessID = "claude-code"
    public let capabilities: HarnessCapabilities = [.runTask, .skillInjection, .traceParsing, .sessionCapture, .baselineIsolation]

    let configPath: String?
    let launcher: any ProcessLauncher
    let resolver: BinaryResolver
    let denylist: Denylist
    let environment: [String: String]
    /// Per-trial watchdog for `run()` (config `runs.timeout`; the executable parses the duration).
    let timeout: Duration
    /// Cap (bytes) on a trial's captured stdout/stderr (config `runs.max_output_bytes`); `nil` ⇒ the
    /// launcher's built-in default. A large-but-valid `stream-json` session must not be truncated into a
    /// false failure — see F7 review round 7.
    let outputLimitBytes: Int?

    /// **`environment` is what this adapter reads to make its own decisions** — which program to run, and
    /// where the session it wrote can be found. It is *not* handed to the program itself: that inherits
    /// this process's environment, which is what the default here is, so the two agree unless a caller
    /// deliberately supplies something else. Handing a caller's map to the program instead would be a
    /// trap: a caller that supplies one variable would leave the program with only that one, and no way
    /// to find anything on the search path.
    ///
    /// **The part that finds the program now reads the same environment.** It used to be built with its
    /// own default whatever this was given, so a caller naming a program through a variable in a supplied
    /// environment was silently ignored and the real one was consulted instead — two components deciding
    /// the same thing from two different sources. Passing one explicitly still overrides, for a caller
    /// that wants exactly that.
    public init(
        configPath: String? = nil,
        launcher: any ProcessLauncher = SubprocessLauncher(),
        resolver: BinaryResolver? = nil,
        denylist: Denylist = .claudeCodeSeed,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: Duration = .seconds(600),
        outputLimitBytes: Int? = nil
    ) {
        self.configPath = configPath
        self.launcher = launcher
        self.resolver = resolver ?? BinaryResolver(environment: environment)
        self.denylist = denylist
        self.environment = environment
        self.timeout = timeout
        self.outputLimitBytes = outputLimitBytes
    }

    public func probe(strict: Bool) async throws -> HarnessInfo {
        guard let resolved = resolver.resolve(
            flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: configPath, pathName: "claude"
        ) else {
            throw EDDError.harnessNotFound(harness: "claude-code", reason: nil)
        }
        // A pinned-but-unreachable binary (bad path/permissions) is "not found", not an opaque crash.
        let output: ProcessOutput
        do {
            output = try await launcher.run(resolved.path, ["--version"], workingDirectory: nil, timeout: .seconds(60), environment: nil, outputLimitBytes: nil)
        } catch {
            throw EDDError.harnessNotFound(harness: "claude-code", reason: nil)
        }
        guard output.exitCode == 0 else { throw EDDError.harnessNotFound(harness: "claude-code", reason: nil) }
        let version = Self.parseVersion(output.stdout)
        // **Only an explicit `1` turns the check off, which is what the message below offers.** Any value
        // at all used to do it, so setting it to `0` — the natural way to write "no, leave the check on" —
        // switched the check off. This is the one switch that lets a version through that is known to
        // produce wrong measurements, so it takes exactly the word the message tells you to use, and
        // anything else leaves the guard in place.
        //
        // Deliberately stricter than the switch that enables the hidden test options, which treats any
        // non-empty value as yes: that one exists so the test harness can turn it *off*, and a harness
        // that overlays variables onto the environment cannot remove one, so it needs empty to mean no.
        // Turning off a safety check is a different kind of decision from enabling a test seam.
        let bypassed = environment["SKILLET_ALLOW_BANNED_CLAUDE_CODE"] == "1"
        var warnings: [String] = []
        var bannedVersion: String?
        switch denylist.check(version: version, pinned: resolved.isPinned, bypassed: bypassed) {
        case .allowed:
            break
        case let .refused(version):
            // Explicitly pinned + banned → hard error, never a silent swap (§9.1).
            throw EDDError.harnessBanned(harness: "claude-code", version: version)
        case let .warnedFallback(version):
            // Auto-discovered + banned: `harness info` warns (not fatal); but `run` (strict) never
            // spends on a known-bad version — refuse here (auto-fallback to another binary is F50).
            if strict {
                throw EDDError.harnessBanned(harness: "claude-code", version: version)
            }
            bannedVersion = version
            warnings.append("claude-code \(version) is on the known-bad denylist (§9.1); "
                + "pin a non-banned version, or set SKILLET_ALLOW_BANNED_CLAUDE_CODE=1 to override")
        }
        // Auth (non-spending): `claude auth status` reports whether a credential is usable. `run`
        // (strict) refuses before spending; `harness info` reports `authenticated: false` without failing.
        let authenticated = await isAuthenticated(binary: resolved.path)
        if strict && !authenticated {
            throw EDDError.harnessUnauthenticated(harness: "claude-code")
        }
        return HarnessInfo(
            id: id,
            version: version,
            authenticated: authenticated,
            available: true,
            warnings: warnings,
            binaryPath: resolved.path,
            source: resolved.source.rawValue,
            bannedVersion: bannedVersion
        )
    }

    /// Verify the resolved binary is authenticated via `claude auth status` — a documented, **non-spending**
    /// check (reads the credential; no model call). Logged in ⇒ exit 0 + `{"loggedIn": true}`. Any error
    /// (non-zero exit, unreachable, unparseable) is treated as not-authenticated.
    private func isAuthenticated(binary: String) async -> Bool {
        guard let output = try? await launcher.run(
            binary, ["auth", "status", "--json"], workingDirectory: nil, timeout: .seconds(30), environment: nil, outputLimitBytes: nil
        ), output.exitCode == 0 else {
            return false
        }
        // Require the structured signal: only an explicit `loggedIn: true` counts. Exit 0 with output
        // that's unparseable or missing `loggedIn` **fails closed** — never spend on an unverified state.
        if let data = output.stdout.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let loggedIn = object["loggedIn"] as? Bool {
            return loggedIn
        }
        return false
    }

    public func verifySkillVisibility(_ skill: SkillRef, strategy: InjectionStrategy) throws {
        // Static $0 positive-load check (§9.2): the *whole* model-visible bundle — SKILL.md,
        // references/, and every other staged entry — must survive the staging filter, or the harness
        // runs with a silently incomplete skill (the --skill-path false-negative class, P6). Doctor's
        // discovery-only (siblings-listable-not-injected) half is unblocked — F14 stages the `visible:`
        // tier live (frontmatter stubs) — and remains deferred, tracked for a later slice (D-4).
        let result = SkillBundleAudit.audit(skillDirectory: URL(fileURLWithPath: skill.path, isDirectory: true))
        if let issue = result.skillMDIssue {
            throw EDDError.skillNotVisible(skill: skill.name, reason: issue)
        }
        if !result.symlinks.isEmpty {
            throw EDDError.skillNotVisible(
                skill: skill.name,
                reason: "staging silently drops symlinked bundle entries: \(result.symlinks.joined(separator: ", "))"
            )
        }
    }

    public func parseTrace(_ raw: RawTrace) throws -> Trace {
        Self.parse(jsonl: raw.raw)
    }

    public func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
        guard let resolved = resolver.resolve(
            flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: configPath, pathName: "claude"
        ) else {
            throw EDDError.harnessNotFound(harness: "claude-code", reason: nil)
        }
        // Honor the injection contract (§9.2): the runner stages skills under the workspace discovery
        // path (`<workspace>/.claude/skills/<name>/`). For `.only`, enforce that each requested skill is
        // actually staged, so a staging failure is caught here rather than silently running skill-less.
        // (Global `~/.claude/skills` can still be discovered on `.only` runs — a documented with-arm
        // limitation. The BASELINE arm (`.none`, F15) is hardened: skills disabled at the session
        // level below, preflighted by `verifyBaselineIsolation()`, tripwire-verified per trial.)
        if case let .only(load, visible) = skills {
            for ref in load {
                let staged = workspace.root.appendingPathComponent(".claude/skills/\(ref.name)/SKILL.md")
                guard FileManager.default.fileExists(atPath: staged.path) else {
                    throw EDDError.skillNotVisible(skill: ref.name, reason: "not staged under the run workspace")
                }
            }
            // The visible tier (F14, §9.2): discoverable-but-stubbed. Enforce the stub is present so a
            // trigger trial can't silently run with an empty selection menu.
            for ref in visible {
                let staged = workspace.root.appendingPathComponent(".claude/skills/\(ref.name)/SKILL.md")
                guard FileManager.default.fileExists(atPath: staged.path) else {
                    throw EDDError.skillNotVisible(skill: ref.name, reason: "stub not staged under the run workspace (visible tier)")
                }
            }
        }
        // `.none` (the F15 baseline arm, §9.2): nothing is staged by the runner, and the session
        // launches with skills disabled so ambient personal skills (`~/.claude/skills`) are
        // provably excluded too — the isolation `verifyBaselineIsolation()` preflights for $0.
        let isolated: Bool = { if case .none = skills { return true } else { return false } }()
        // The watchdog (`timeout`) and the sandbox cwd are enforced by the launcher; a non-zero exit
        // means the trial could not run.
        let output = try await launcher.run(
            resolved.path,
            Self.runArguments(prompt: task.query, isolated: isolated),
            workingDirectory: workspace.root.path,
            timeout: timeout,
            environment: nil,
            outputLimitBytes: outputLimitBytes
        )
        guard output.exitCode == 0 else {
            throw HarnessError.executionFailed(harness: "claude-code", exitCode: output.exitCode, stderr: output.stderr)
        }
        return RawTrace(harness: id, raw: output.stdout)
    }

    /// The claude-code one-shot invocation (`-p`/print) that emits the session as JSONL on stdout for
    /// `parseTrace`. `stream-json` requires `--verbose`; `acceptEdits` lets file-writing evals proceed
    /// unattended inside the throwaway per-trial workspace. This live flag contract is validated/tuned
    /// by F7's env-gated smoke (claude-code isn't runnable in CI) — the arg *shape* is unit-tested here.
    /// `isolated` (F15, the `.none` baseline arm) appends the session-level no-skills switch — the
    /// surgical choice over `--bare`/`--safe-mode`, which also strip CLAUDE.md/hooks and would make
    /// the two arms differ by more than the skill.
    static func runArguments(prompt: String, isolated: Bool = false) -> [String] {
        var args = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits"]
        if isolated { args.append(Self.isolationFlag) }
        return args
    }

    /// The session-level switch that disables all skills and commands (documented in the claude-code
    /// CLI reference) — how a `.none` baseline excludes ambient personal skills without touching
    /// auth or the config dir.
    static let isolationFlag = "--disable-slash-commands"

    /// The $0 `--ab` preflight (F15, §9.2): prove the resolved binary supports the isolation switch
    /// before any paid baseline trial — flag support shifts across harness versions (the denylist
    /// class), so it is checked per run, never assumed. The per-trial pollution tripwire (RunKit)
    /// then verifies the switch actually held, from the parsed trace.
    public func verifyBaselineIsolation() async throws {
        guard let resolved = resolver.resolve(
            flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: configPath, pathName: "claude"
        ) else {
            throw EDDError.harnessNotFound(harness: "claude-code", reason: nil)
        }
        let output: ProcessOutput
        do {
            output = try await launcher.run(resolved.path, ["--help"], workingDirectory: nil, timeout: .seconds(60), environment: nil, outputLimitBytes: nil)
        } catch {
            throw EDDError.baselineNotIsolable(
                harness: "claude-code",
                reason: "could not interrogate the resolved binary (`claude --help` failed)"
            )
        }
        guard output.exitCode == 0, output.stdout.contains(Self.isolationFlag) else {
            throw EDDError.baselineNotIsolable(
                harness: "claude-code",
                reason: "the resolved binary does not advertise \(Self.isolationFlag), so ambient personal skills cannot be provably excluded from the baseline arm"
            )
        }
    }

    public func locateSessions(_ query: SessionQuery) async throws -> [NativeSessionRef] {
        let workspace = query.workspace ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        return Self.locate(projectsRoot: root, workspace: workspace, environment: environment)
    }

    public func exportSession(_ ref: NativeSessionRef) async throws -> RawTrace {
        let url = URL(fileURLWithPath: ref.path)
        // Read the session through the one sanctioned untrusted reader (T10 — this was a private copy of
        // the same guards): never follow a symlink (could redirect to an arbitrary host file), never open a
        // special file (a FIFO/socket read blocks forever), never read a hard link (another inode). Refuse
        // an OVERSIZED session rather than silently truncating it — `parse` is lenient and would drop the
        // malformed last line, yielding an incomplete Trace with no error, so capture would write + score a
        // truncated bundle. (Confining a user-supplied `--session` path is the command's job; `--last`
        // reads the trusted store.)
        let cap = 64 << 20
        switch SafeFile.readPlainData(url, cap: cap) {
        case let .success(data):
            guard let raw = String(data: data, encoding: .utf8) else {
                throw HarnessError.executionFailed(harness: "claude-code", exitCode: -1,
                    stderr: "could not read native session at \(ref.path)")
            }
            return RawTrace(harness: id, raw: raw)
        case let .failure(.oversized(size, _)):
            throw HarnessError.executionFailed(harness: "claude-code", exitCode: -1,
                stderr: "native session at \(ref.path) is \(size) bytes — exceeds the \(cap / (1 << 20)) MiB cap; refusing to capture a truncated bundle")
        case .failure(.symlink), .failure(.notRegularFile), .failure(.hardLink):
            throw HarnessError.executionFailed(harness: "claude-code", exitCode: -1,
                stderr: "refusing to read native session at \(ref.path): not a plain regular file (symlink/special/hard link)")
        case .failure:   // notFound / unreadable — `readPlainData`'s only other refusals
            throw HarnessError.executionFailed(harness: "claude-code", exitCode: -1,
                stderr: "could not read native session at \(ref.path)")
        }
    }

    /// claude-code keys its per-project session store by the workspace path via `replace(/[^a-zA-Z0-9]/g,
    /// "-")` — **every** character that isn't ASCII `[A-Za-z0-9]` becomes `-` (spaces + punctuation, not
    /// just `/._`; case and runs of dashes are preserved). Verified against claude-code 2.1.195's encoder
    /// and the live store (`/Users/x/Developer/skillet` → `-Users-x-Developer-skillet`; `/.skillet` →
    /// `--skillet`; `/Users/x/My App` → `-Users-x-My-App`). We must reproduce it exactly or `--last` /
    /// store lookup silently fails to resolve a real session under a space/punctuation path.
    ///
    /// Limitation: claude truncates an encoding longer than 200 chars and appends a private hash we can't
    /// reproduce; a workspace whose encoded path exceeds 200 chars won't resolve via the store and must use
    /// `--session <path>` (the longest live store dir is ~117 chars, so this is deep-nesting-only).
    static func claudeProjectDirName(for workspace: URL) -> String {
        String(workspace.standardizedFileURL.path.map { c in
            c.isASCII && (c.isLetter || c.isNumber) ? c : "-"
        })
    }

    /// The locate logic, over an injectable `projectsRoot` (so tests point it at a temp store). Returns
    /// the workspace's session files **newest-first**, excluding skillet's own in-flight session when the
    /// harness exported its id/file (`$CLAUDE_SESSION_ID` / `$CLAUDE_SESSION_FILE`). An absent store dir
    /// yields `[]` (the command surfaces "no session found"); the command takes the newest pick +
    /// confirm-if-ambiguous (§3.2).
    static func locate(
        projectsRoot: URL, workspace: URL, environment: [String: String], fileManager: FileManager = .default
    ) -> [NativeSessionRef] {
        let storeDir = projectsRoot.appendingPathComponent(claudeProjectDirName(for: workspace), isDirectory: true)
        // Refuse a symlinked store dir (it could redirect the whole lookup elsewhere), then keep only plain
        // regular, non-hard-linked `*.jsonl` below (a symlinked/hard-linked entry could point
        // `exportSession` at an arbitrary host file).
        guard !SafeFile.isSymlink(storeDir), let entries = try? fileManager.contentsOfDirectory(
            at: storeDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return [] }

        let excludedStems = Set([environment["CLAUDE_SESSION_ID"]].compactMap { $0 })
        let excludedPaths = Set([environment["CLAUDE_SESSION_FILE"]].compactMap {
            $0.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        })
        func mtime(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return entries
            .filter { $0.pathExtension == "jsonl" }
            .filter { !SafeFile.isSymlink($0) && SafeFile.isRegularFile($0) && SafeFile.linkCount($0) == 1 }   // safe files only
            .filter { !excludedStems.contains($0.deletingPathExtension().lastPathComponent) }
            .filter { !excludedPaths.contains($0.standardizedFileURL.path) }
            .sorted { mtime($0) > mtime($1) }
            .map { NativeSessionRef(id: $0.deletingPathExtension().lastPathComponent, path: $0.standardizedFileURL.path) }
    }

    // MARK: - Parsing (native session JSONL → Trace)

    /// Parse claude-code's native session JSONL into the normalized `Trace`. Control lines
    /// (`ai-title`/`last-prompt`/`queue-operation`/`attachment`/`system`) are skipped. Real
    /// conversational turns are `assistant` lines and `user` lines that carry `text` — a `user` line
    /// whose content is only `tool_result` blocks is the back-half of a tool round-trip, **not a
    /// turn** (in real sessions these outnumber genuine user turns ~5:1), so it does not become a
    /// `Turn`. The authoritative workspace diff comes from each result line's `toolUseResult`
    /// (`create`→added, `update`→modified) — the request input only attributes per-turn
    /// `filesTouched`. A `tool_use` named `Skill` is a skill invocation. `usage` stays `nil` (v1.x,
    /// §13); deletions and failed/`is_error` tool results are not yet modeled (documented F6 gaps).
    /// Lenient by design — a malformed line is skipped, never fatal.
    static func parse(jsonl: String) -> Trace {
        var turns: [Turn] = []
        var skillInvocations: [SkillInvocation] = []
        var created: [String] = []
        var updated: [String] = []
        var version = "unknown"
        var startedAt: Date?
        var endedAt: Date?
        var counted: TokenCounts?
        /// A reply reported counts this parser could not read. The session total would be short, so it
        /// reports nothing rather than something incomplete that looks complete.
        var countsUnreadable = false

        // **Split on any line ending, not on one particular character.** A file saved with Windows line
        // endings does not degrade line by line here — it does not split at all. In Swift a carriage
        // return followed by a newline is a *single* character, so asking to split on a newline never
        // matches it, and the entire session arrives as one piece that is not valid on its own. Measured:
        // a two-reply session read this way yields no conversation at all and no counts. The grader then
        // reads an empty conversation and fails every expectation — a measured failure produced by how a
        // file was saved, with nothing anywhere saying so.
        //
        // This project already documents the same trap where it stages a skill file; that reader
        // normalises first. This one did not, which is the same rule holding in one place and missing
        // from another.
        for line in jsonl.split(whereSeparator: \.isNewline) {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = object["type"] as? String, type == "user" || type == "assistant" else { continue }

            if let v = object["version"] as? String { version = v }
            if let stamp = (object["timestamp"] as? String).flatMap(Self.parseTimestamp) {
                if startedAt == nil { startedAt = stamp }
                endedAt = stamp
            }

            // Authoritative file changes come from the result, not the request (a requested-but-failed
            // Write must not count). `toolUseResult` rides on the `user` tool_result line.
            if let result = object["toolUseResult"] as? [String: Any],
               let filePath = result["filePath"] as? String {
                switch result["type"] as? String {
                case "create": created.append(filePath)
                case "update": updated.append(filePath)
                default: break
                }
            }

            let message = object["message"] as? [String: Any]
            // **The token counts were already on these lines and were being thrown away.** Each reply the
            // model sends reports what it read and wrote for that reply; adding them up over the session
            // gives what the whole attempt read and wrote. Re-sent context is counted again each time,
            // which is right — the model did read it again, and that is what a provider bills on.
            //
            // Read field by field, never by summing something already summed: the provider's own
            // `input_tokens` holds *only* the part that missed its cache, so the other two are separate
            // additions rather than a breakdown of it. Getting that backwards is the doubling bug this
            // project's ``TokenCounts`` documentation names.
            // **Only the model's own replies are read for counts.** Both kinds of line reach this point,
            // and both used to be read, while the note above says the counts come from each reply the
            // model sends. Measured across every session on this machine — 24,598 lines of ten kinds —
            // only the model's replies carry a count block, 11,246 of them. More to the point, tokens
            // spent on results handed back from a tool are already inside the *next* reply's input
            // figure, because that is what the model then reads. So the replies are the whole of the
            // accounting rather than part of it, and a count found anywhere else could only be those same
            // tokens stated a second time — the roughly-doubling fault this file already documents.
            if type == "assistant", let usage = message?["usage"] as? [String: Any] {
                // **All four or the whole session counts nothing.** Substituting zero for a field that is
                // missing turns a half-reported reply into a confident under-count — the same invented
                // number this file stopped writing, arriving by a different door. And a single unreadable
                // reply makes the *session* total short, so it poisons the whole answer rather than only
                // its own line: an under-count presented as complete is worse than no count, because
                // nothing about it looks wrong.
                //
                // Every one of the 10,833 replies across the sessions on this machine carries all four,
                // so this cannot be reached today. That is the reason to enforce it rather than describe
                // it: an invariant the code does not check is prose, and the next change to what a
                // provider sends decides whether it was ever true.
                //
                // **Only the counting is abandoned — the reply itself is kept.** Skipping ahead here also
                // skipped the code below that turns this line into part of the conversation, so a reply
                // whose counts were unreadable vanished from the transcript entirely. The automatic
                // grader reads that transcript, so losing the model's last reply could turn a pass into a
                // failure with nothing anywhere recording that a line had gone missing. One unreadable
                // number must not cost a whole reply.
                if let uncached = usage["input_tokens"] as? Int,
                   let cacheRead = usage["cache_read_input_tokens"] as? Int,
                   let cacheWrite = usage["cache_creation_input_tokens"] as? Int,
                   let output = usage["output_tokens"] as? Int,
                   // A count below none is refused where the value is built, and a reply reporting one is
                   // no more usable than a reply missing a field — so it takes the same path.
                   let turnCounts = TokenCounts(uncachedInput: uncached, cacheRead: cacheRead,
                                                cacheWrite: cacheWrite, output: output) {
                    // A running total too large to record takes the same path as an unreadable reply:
                    // the session's counts are withheld rather than stated wrongly.
                    if let running = counted {
                        if let sum = running + turnCounts { counted = sum } else { countsUnreadable = true }
                    } else {
                        counted = turnCounts
                    }
                } else {
                    countsUnreadable = true
                }
            }
            let role: Turn.Role = (message?["role"] as? String) == "assistant" ? .assistant : .user
            let content = message?["content"] as? [[String: Any]] ?? []

            // A user line with no `text` block is a tool-result round-trip, not a turn (Gap A).
            let hasText = content.contains { $0["type"] as? String == "text" }
            if role == .user && !hasText { continue }

            let turnIndex = turns.count
            var texts: [String] = []
            var toolCalls: [ToolCall] = []
            var filesTouched: [String] = []

            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let t = block["text"] as? String { texts.append(t) }
                case "tool_use":
                    let name = block["name"] as? String ?? ""
                    let input = block["input"] as? [String: Any]
                    toolCalls.append(ToolCall(name: name, input: Self.encodeInput(input)))
                    if name == "Skill", let skill = input?["skill"] as? String {
                        skillInvocations.append(SkillInvocation(skill: skill, turnIndex: turnIndex))
                    }
                    if let filePath = input?["file_path"] as? String { filesTouched.append(filePath) }
                default:
                    break
                }
            }
            turns.append(Turn(role: role, text: texts.joined(separator: "\n"), toolCalls: toolCalls, filesTouched: filesTouched, at: stampOrEpoch(startedAt, endedAt)))
        }

        let added = Array(Set(created)).sorted()
        let modified = Array(Set(updated).subtracting(added)).sorted()
        let zero = Date(timeIntervalSince1970: 0)
        return Trace(
            harness: "claude-code",
            harnessVersion: version,
            startedAt: startedAt ?? zero,
            endedAt: endedAt ?? startedAt ?? zero,
            turns: turns,
            skillInvocations: skillInvocations,
            workspaceDiff: WorkspaceDiff(added: added, modified: modified, deleted: []),
            // `nil` when no reply reported counts, and also when one reported counts that could not be
            // read — a short total presented as a whole one is the fault this replaced.
            usage: countsUnreadable ? nil : counted,
            // **Which of those two it was.** Both come out as no figures, deliberately; only one is a
            // problem worth telling someone about, and until now nothing recorded which had happened.
            usageState: countsUnreadable ? .unreadable : (counted == nil ? .absent : .counted)
        )
    }

    /// **The second argument is "the line being read", not "the end of the session".** It is reassigned on
    /// every line as the file is walked, and each turn is stamped at the moment it is added — so a turn
    /// gets *its own* line's time. The name reads as the session's final stamp, which is only what it
    /// holds once the walk is over, and that has now been reported twice as a bug where each turn
    /// supposedly gets the session's end time. It does not: `ParseTraceTests` covers exactly this, under
    /// the name "Each turn carries ITS OWN line timestamp, not the session's final one".
    private static func stampOrEpoch(_ started: Date?, _ ended: Date?) -> Date {
        ended ?? started ?? Date(timeIntervalSince1970: 0)
    }

    static func encodeInput(_ input: [String: Any]?) -> String? {
        guard let input, let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func parseVersion(_ output: String) -> String {
        if let match = output.firstMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) {
            return String(match.0)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseTimestamp(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
