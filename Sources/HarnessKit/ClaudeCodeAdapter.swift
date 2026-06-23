import Foundation
import EDDCore
import TraceKit

/// The first real harness adapter (F6). Ships the **validatable** surface: parse claude-code's native
/// session JSONL → `Trace`, resolve + vet its binary (`probe`), and the static skill-visibility check.
/// The live task execution (`run` + §9.2 skill-injection) lands in F7; `probe`'s live `--version` call
/// is exercised here only via the injected `ProcessLauncher` (the real call is env-gated in F7).
public struct ClaudeCodeAdapter: HarnessAdapter {
    public let id: HarnessID = "claude-code"
    public let capabilities: HarnessCapabilities = [.runTask, .skillInjection, .traceParsing, .sessionCapture]

    let configPath: String?
    let launcher: any ProcessLauncher
    let resolver: BinaryResolver
    let denylist: Denylist
    let environment: [String: String]

    public init(
        configPath: String? = nil,
        launcher: any ProcessLauncher = SubprocessLauncher(),
        resolver: BinaryResolver = BinaryResolver(),
        denylist: Denylist = .claudeCodeSeed,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.configPath = configPath
        self.launcher = launcher
        self.resolver = resolver
        self.denylist = denylist
        self.environment = environment
    }

    public func probe() async throws -> HarnessInfo {
        guard let resolved = resolver.resolve(
            flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: configPath, pathName: "claude"
        ) else {
            throw EDDError.harnessNotFound(harness: "claude-code")
        }
        let output = try await launcher.run(resolved.path, ["--version"])
        guard output.exitCode == 0 else { throw EDDError.harnessNotFound(harness: "claude-code") }
        let version = Self.parseVersion(output.stdout)
        let bypassed = environment["SKILLET_ALLOW_BANNED_CLAUDE_CODE"] != nil
        if case let .refused(version) = denylist.check(version: version, pinned: resolved.isPinned, bypassed: bypassed) {
            throw EDDError.harnessBanned(harness: "claude-code", version: version)
        }
        // Auth: a real check is env-gated (F7). F6 reports available + assumes authenticated.
        return HarnessInfo(id: id, version: version, authenticated: true, available: true)
    }

    public func verifySkillVisibility(_ skill: SkillRef, strategy: InjectionStrategy) throws {
        // Static $0 check (§9.2): the target SKILL.md must resolve under the discovery path. The
        // discovery-only (siblings-listable-not-injected) half is refined when validated live (F7/F3).
        let skillFile = URL(fileURLWithPath: skill.path).appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillFile.path) else {
            throw EDDError.skillNotVisible(skill: skill.name, reason: "no SKILL.md at \(skill.path)")
        }
    }

    public func parseTrace(_ raw: RawTrace) throws -> Trace {
        Self.parse(jsonl: raw.raw)
    }

    public func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
        throw HarnessError.notImplemented("live claude-code execution lands in F7")
    }

    public func locateSessions(_ query: SessionQuery) async throws -> [NativeSessionRef] {
        throw HarnessError.notImplemented("session capture lands in Phase 3")
    }

    public func exportSession(_ ref: NativeSessionRef) async throws -> RawTrace {
        throw HarnessError.notImplemented("session capture lands in Phase 3")
    }

    // MARK: - Parsing (native session JSONL → Trace)

    /// Parse claude-code's native session JSONL into the normalized `Trace`. Control lines
    /// (`ai-title`/`last-prompt`/`queue-operation`/`attachment`) are skipped; `user`/`assistant`
    /// lines become turns; a `tool_use` named `Skill` is a skill invocation; `Write`/`Edit` file
    /// paths feed the workspace diff. `usage` stays `nil` (v1.x, §13). Lenient by design — a
    /// malformed line is skipped, never fatal.
    static func parse(jsonl: String) -> Trace {
        var turns: [Turn] = []
        var skillInvocations: [SkillInvocation] = []
        var written: [String] = []
        var edited: [String] = []
        var version = "unknown"
        var startedAt: Date?
        var endedAt: Date?

        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = object["type"] as? String, type == "user" || type == "assistant" else { continue }

            if let v = object["version"] as? String { version = v }
            if let stamp = (object["timestamp"] as? String).flatMap(Self.parseTimestamp) {
                if startedAt == nil { startedAt = stamp }
                endedAt = stamp
            }

            let message = object["message"] as? [String: Any]
            let role: Turn.Role = (message?["role"] as? String) == "assistant" ? .assistant : .user
            let content = message?["content"] as? [[String: Any]] ?? []
            let turnIndex = turns.count
            var text = ""
            var toolCalls: [ToolCall] = []
            var filesTouched: [String] = []

            for block in content {
                switch block["type"] as? String {
                case "text":
                    text += block["text"] as? String ?? ""
                case "tool_use":
                    let name = block["name"] as? String ?? ""
                    let input = block["input"] as? [String: Any]
                    toolCalls.append(ToolCall(name: name, input: Self.encodeInput(input)))
                    if name == "Skill", let skill = input?["skill"] as? String {
                        skillInvocations.append(SkillInvocation(skill: skill, turnIndex: turnIndex))
                    }
                    if let filePath = input?["file_path"] as? String {
                        filesTouched.append(filePath)
                        if name == "Write" { written.append(filePath) } else if name == "Edit" { edited.append(filePath) }
                    }
                default:
                    break
                }
            }
            turns.append(Turn(role: role, text: text, toolCalls: toolCalls, filesTouched: filesTouched, at: stampOrEpoch(startedAt, endedAt)))
        }

        let added = Array(Set(written)).sorted()
        let modified = Array(Set(edited).subtracting(added)).sorted()
        let zero = Date(timeIntervalSince1970: 0)
        return Trace(
            harness: "claude-code",
            harnessVersion: version,
            startedAt: startedAt ?? zero,
            endedAt: endedAt ?? startedAt ?? zero,
            turns: turns,
            skillInvocations: skillInvocations,
            workspaceDiff: WorkspaceDiff(added: added, modified: modified, deleted: []),
            usage: nil
        )
    }

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
