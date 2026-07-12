import Testing
import Foundation
import EDDCore
import TraceKit
import HarnessKit

@Suite("claude-code run (seam)")
struct RunTests {
    /// A tiny but valid claude-code session: one assistant turn that fires the demo Skill and writes a
    /// file, the tool-result round-trip, then a closing turn.
    static let sessionJSONL = """
    {"type":"assistant","version":"2.1.146","timestamp":"2025-01-01T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"working"},{"type":"tool_use","name":"Skill","input":{"skill":"demo"}},{"type":"tool_use","name":"Write","input":{"file_path":"out.txt"}}]}}
    {"type":"user","timestamp":"2025-01-01T00:00:01.000Z","toolUseResult":{"type":"create","filePath":"out.txt"},"message":{"role":"user","content":[{"type":"tool_result"}]}}
    {"type":"assistant","timestamp":"2025-01-01T00:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}
    """

    private func adapter(launcher: any ProcessLauncher, pathLookup: [String: String] = ["claude": "/usr/bin/claude"], timeout: Duration = .seconds(600), outputLimitBytes: Int? = nil) -> ClaudeCodeAdapter {
        ClaudeCodeAdapter(
            launcher: launcher,
            resolver: BinaryResolver(probe: FakeExecutableProbe(pathLookup: pathLookup), environment: [:]),
            environment: [:],
            timeout: timeout,
            outputLimitBytes: outputLimitBytes
        )
    }

    @Test("run() threads the configured output capture limit to the launcher")
    func runForwardsOutputLimit() async throws {
        let launcher = RecordingLauncher(output: ProcessOutput(stdout: Self.sessionJSONL, stderr: "", exitCode: 0))
        _ = try await adapter(launcher: launcher, outputLimitBytes: 123_456)
            .run(TaskSpec(query: "go"), in: Workspace(root: URL(fileURLWithPath: "/tmp/ws")), skills: .ambient)
        #expect(await launcher.outputLimitBytes == 123_456)
    }

    @Test("run() resolves the binary, runs in the sandbox with the watchdog, returns stdout as a RawTrace")
    func runReturnsTrace() async throws {
        let launcher = RecordingLauncher(output: ProcessOutput(stdout: Self.sessionJSONL, stderr: "", exitCode: 0))
        let workspace = Workspace(root: URL(fileURLWithPath: "/tmp/skillet-ws"))
        let raw = try await adapter(launcher: launcher, timeout: .seconds(120))
            .run(TaskSpec(query: "make out.txt"), in: workspace, skills: .ambient)
        #expect(raw.harness == "claude-code")
        #expect(raw.raw == Self.sessionJSONL)
        // The call actually carried the resolved binary, the prompt in a print-mode stream-json
        // invocation, the sandbox cwd, and the per-trial watchdog.
        #expect(await launcher.executable == "/usr/bin/claude")
        #expect(await launcher.arguments.contains("-p"))
        #expect(await launcher.arguments.contains("make out.txt"))
        #expect(await launcher.arguments.contains("stream-json"))
        #expect(await launcher.arguments.contains("--verbose"))
        #expect(await launcher.workingDirectory == "/tmp/skillet-ws")
        #expect(await launcher.timeout == .seconds(120))
    }

    @Test("The RawTrace from run() parses into a Trace (skill invocation + created file)")
    func runOutputParses() async throws {
        let a = adapter(launcher: FakeLauncher(output: ProcessOutput(stdout: Self.sessionJSONL, stderr: "", exitCode: 0)))
        let raw = try await a.run(TaskSpec(query: "go"), in: Workspace(root: URL(fileURLWithPath: "/tmp/ws")), skills: .ambient)
        let trace = try a.parseTrace(raw)
        #expect(trace.skillInvocations.map(\.skill) == ["demo"])
        #expect(trace.workspaceDiff.added == ["out.txt"])
    }

    @Test("A non-zero claude exit surfaces as executionFailed, not a silent empty trace")
    func runNonZeroExit() async {
        let launcher = FakeLauncher(output: ProcessOutput(stdout: "", stderr: "boom", exitCode: 2))
        await #expect(throws: HarnessError.executionFailed(harness: "claude-code", exitCode: 2, stderr: "boom")) {
            try await adapter(launcher: launcher).run(TaskSpec(query: "go"), in: Workspace(root: URL(fileURLWithPath: "/tmp/ws")), skills: .ambient)
        }
    }

    @Test("run() with no resolvable binary throws (not found)")
    func runNotFound() async {
        let launcher = FakeLauncher(output: ProcessOutput(stdout: "", stderr: "", exitCode: 0))
        await #expect(throws: EDDError.self) {
            try await adapter(launcher: launcher, pathLookup: [:]).run(TaskSpec(query: "go"), in: Workspace(root: URL(fileURLWithPath: "/tmp/ws")), skills: .ambient)
        }
    }

    @Test("run() honors .only: a requested skill not staged in the workspace throws skillNotVisible")
    func onlyInjectionUnstaged() async {
        let launcher = FakeLauncher(output: ProcessOutput(stdout: Self.sessionJSONL, stderr: "", exitCode: 0))
        let ws = Workspace(root: URL(fileURLWithPath: "/tmp/skillet-empty-\(UUID().uuidString)"))
        await #expect(throws: EDDError.self) {
            try await adapter(launcher: launcher).run(TaskSpec(query: "go"), in: ws, skills: .only(load: [SkillRef(name: "demo", path: "/x")]))
        }
    }

    @Test("run() honors .only: a staged skill passes the check and runs")
    func onlyInjectionStaged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let staged = root.appendingPathComponent(".claude/skills/demo")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try "x".write(to: staged.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = FakeLauncher(output: ProcessOutput(stdout: Self.sessionJSONL, stderr: "", exitCode: 0))
        let raw = try await adapter(launcher: launcher)
            .run(TaskSpec(query: "go"), in: Workspace(root: root), skills: .only(load: [SkillRef(name: "demo", path: staged.path)]))
        #expect(raw.harness == "claude-code")
    }
}

/// Exercises the *real* `SubprocessLauncher` against ubiquitous posix binaries — the only way to prove
/// the F7 cwd / timeout / environment additions actually reach (and bound) the child process.
@Suite("SubprocessLauncher (real process)")
struct SubprocessLauncherTests {
    @Test("Captures stdout + exit code (no watchdog path)")
    func echoes() async throws {
        let out = try await SubprocessLauncher().run("/bin/echo", ["hi"], workingDirectory: nil, timeout: nil, environment: nil, outputLimitBytes: nil)
        #expect(out.stdout == "hi\n")
        #expect(out.exitCode == 0)
    }

    @Test("A bare executable name resolves via PATH (a SKILLET_*_BIN / config bare name must exec)")
    func bareNameResolvesViaPath() async throws {
        // `echo` (no `/`) must be found on PATH, not treated as the relative path `./echo`.
        let out = try await SubprocessLauncher().run("echo", ["hi"], workingDirectory: nil, timeout: nil, environment: nil, outputLimitBytes: nil)
        #expect(out.stdout == "hi\n" && out.exitCode == 0)
    }

    @Test("workingDirectory sets the child's cwd")
    func setsWorkingDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("MARKER.txt").path, contents: Data())
        let out = try await SubprocessLauncher().run("/bin/ls", [], workingDirectory: dir.path, timeout: nil, environment: nil, outputLimitBytes: nil)
        #expect(out.stdout.contains("MARKER.txt"))
    }

    @Test("environment overlay reaches the child (layered on the inherited env)")
    func overlaysEnvironment() async throws {
        let out = try await SubprocessLauncher().run("/usr/bin/env", [], workingDirectory: nil, timeout: nil, environment: ["SKILLET_TEST_VAR": "hello123"], outputLimitBytes: nil)
        #expect(out.stdout.contains("SKILLET_TEST_VAR=hello123"))
    }

    @Test("A child that wins the race returns its real output, watchdog notwithstanding")
    func underTimeoutReturns() async throws {
        let out = try await SubprocessLauncher().run("/bin/echo", ["fast"], workingDirectory: nil, timeout: .seconds(10), environment: nil, outputLimitBytes: nil)
        #expect(out.stdout == "fast\n")
    }

    @Test("A child that overruns the watchdog is killed and surfaces timedOut")
    func overTimeoutThrows() async {
        await #expect(throws: ProcessError.self) {
            try await SubprocessLauncher().run("/bin/sleep", ["3"], workingDirectory: nil, timeout: .milliseconds(200), environment: nil, outputLimitBytes: nil)
        }
    }

    // F26/F32 walking-skeleton: prove `input:` actually pipes stdin to the child. `cat` echoes stdin →
    // stdout, so a round-trip proves the buffer reached the process (the mile the isolated spike showed
    // and this bakes into the suite). A secret-shaped payload also confirms no truncation/encoding loss.
    @Test("input: pipes stdin to the child (round-trips through cat)")
    func pipesStdin() async throws {
        let payload = "github_token = ghp_skilletSyntheticCanaryDoNotUse123456\nsecond line\n"
        let out = try await SubprocessLauncher().run(
            "/bin/cat", [], input: Data(payload.utf8),
            workingDirectory: nil, timeout: .seconds(10), environment: nil, outputLimitBytes: nil)
        #expect(out.stdout == payload)
        #expect(out.exitCode == 0)
    }

    @Test("Small output still captures normally under a generous default limit")
    func smallOutputUnderDefault() async throws {
        let out = try await SubprocessLauncher().run("/bin/echo", ["hi"], workingDirectory: nil, timeout: nil, environment: nil, outputLimitBytes: nil)
        #expect(out.stdout == "hi\n")   // nil ⇒ 64 MiB default, well above this
    }

    @Test("Output exceeding outputLimitBytes throws (a capture cap, not a silent truncation)")
    func outputLimitCapsCapture() async {
        await #expect(throws: (any Error).self) {
            _ = try await SubprocessLauncher().run("/bin/echo", [String(repeating: "x", count: 500)], workingDirectory: nil, timeout: nil, environment: nil, outputLimitBytes: 8)
        }
    }
}
