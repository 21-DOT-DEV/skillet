import Testing
import Foundation
import Clocks
import EDDCore
import TraceKit
@testable import HarnessKit   // givingUpAfter is an internal helper, deliberately not public API
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
@Suite("SubprocessLauncher (real process)", .timeLimit(.minutes(1)))
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
        try #require(FileManager.default.createFile(atPath: dir.appendingPathComponent("MARKER.txt").path, contents: Data()),
                     "if the marker was never written, the listing below would come back empty and read as a working directory that was never set")
        let out = try await SubprocessLauncher().run("/bin/ls", [], workingDirectory: dir.path, timeout: nil, environment: nil, outputLimitBytes: nil)
        #expect(out.stdout.contains("MARKER.txt"))
    }

    @Test("environment overlay reaches the child (layered on the inherited env)")
    func overlaysEnvironment() async throws {
        let out = try await SubprocessLauncher().run("/usr/bin/env", [], workingDirectory: nil, timeout: nil, environment: ["SKILLET_TEST_VAR": "hello123"], outputLimitBytes: nil)
        #expect(out.stdout.contains("SKILLET_TEST_VAR=hello123"))
    }

    /// The limit stays in the picture — this check is about a program finishing before it — but it is
    /// measured on a clock this check never moves, so it can never fire however busy the machine is. Ten
    /// seconds of real time used to stand here, which was a bet that the machine would finish a `/bin/echo`
    /// within ten seconds; generous, but still a guess about speed rather than a statement about the code.
    @Test("A child that wins the race returns its real output, watchdog notwithstanding")
    func underTimeoutReturns() async throws {
        let out = try await SubprocessLauncher(clock: TestClock()).run(
            "/bin/echo", ["fast"], workingDirectory: nil, timeout: .seconds(10),
            environment: nil, outputLimitBytes: nil)
        #expect(out.stdout == "fast\n")
    }

    /// **Nothing is started here and nothing waits.** The work is a wait on a clock nobody ever moves,
    /// which is simply a wait that never ends. The watchdog's clock reports the time up the instant it is
    /// asked. So the outcome is settled by construction rather than by one side being slower than the
    /// other, and there is no elapsed time anywhere for a busy machine to stretch.
    ///
    /// Three earlier versions of this raced a real ten-minute program against a clock and each lost in a
    /// different way — the last of them failing five times in ten under load (Specs/020 §10, rounds
    /// fifty-three, fifty-four, fifty-seven). All three existed only because giving up after a while used
    /// to be welded to starting a program, so the giving-up could not be checked on its own. It can now.
    @Test("Work that outlasts the watchdog is abandoned, and the caller is told the time ran out")
    func givingUpReportsTimedOut() async throws {
        let neverArrives = TestClock()      // never moved on, so anything waiting on it waits for good
        do {
            _ = try await SubprocessLauncher.givingUpAfter(.seconds(1), on: ImmediateClock()) {
                try await neverArrives.sleep(for: .seconds(1))
                return "the work finished, which it cannot"
            }
            Issue.record("the watchdog should have given up on work that never finishes")
        } catch let error as ProcessError {
            guard case .timedOut(let waited) = error else {
                Issue.record("expected the watchdog's own error, got \(error)"); return
            }
            #expect(waited == .seconds(1), "the report must say how long it waited before giving up")
        }
    }


    /// **That a program this tool walks away from is actually ended.** Nothing checked this before: the
    /// deleted check that claimed it in its title only ever confirmed the caller was told the time had run
    /// out. If ending it ever stopped working, this tool would abandon model programs that keep running —
    /// and those are billed by the minute, which is a poor look for a tool that reports spending.
    ///
    /// Walking away is what a time limit does under the covers, so that is what is triggered here directly,
    /// which also keeps the steps in order: a limit that reports the time up at once would end the program
    /// before it had managed to record anything. No duration is guessed at any point — each step asks
    /// repeatedly whether a condition holds and gives up after a number of tries, which is a different
    /// thing from waiting out a chosen length of time.
    /// The bound matters here: the program under this check never finishes by itself, so if walking away
    /// stopped ending it, there would be nothing left to end the run. The bound turns that into a reported
    /// failure instead of a run that never finishes.
    @Test("A program this tool walks away from is actually ended, not left running", .timeLimit(.minutes(1)))
    func abandonedChildIsActuallyEnded() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let note = dir.appendingPathComponent("pid")
        let script = dir.appendingPathComponent("blocks")
        try "#!/bin/sh\necho $$ > '\(note.path)'\nexec tail -f /dev/null\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let running = Task {
            try await SubprocessLauncher().run(script.path, [], workingDirectory: nil,
                                               timeout: nil, environment: nil, outputLimitBytes: nil)
        }
        // If the program never records its number, this waits until the check's own time limit ends it.
        try await Self.keepAsking { FileManager.default.fileExists(atPath: note.path) }

        let noted = try String(contentsOf: note, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try #require(pid_t(noted), "the recorded number was not readable")
        #expect(kill(pid, 0) == 0, "the program should still be running at this point")

        running.cancel()
        _ = await running.result
        // Stops answering → it has been ended and cleared away. If it never stops answering — the program
        // was left running, which is the failure this check exists for — the time limit ends the check.
        try await Self.keepAsking { kill(pid, 0) != 0 }
    }

    /// Asks `condition` over and over until it holds, pausing briefly between attempts.
    ///
    /// **There is no attempt count, deliberately.** A first version gave up after five hundred attempts —
    /// about five seconds — and that turned out to be a bet on machine speed exactly like the ones this
    /// project spent days removing: it held when this check ran on its own and was exceeded when the whole
    /// suite ran at once and starting a program took longer. The only bound now is the time limit on the
    /// check itself, so there is one number in play instead of two that can disagree, and it is a failure
    /// bound rather than a race. Being told to stop is passed on rather than swallowed — that is how the
    /// time limit ends this, and it is why a run that was stopped says so instead of inventing a failure.
    private static func keepAsking(_ condition: () -> Bool) async throws {
        while !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // F26/F32 walking-skeleton: prove `input:` actually pipes stdin to the child. `cat` echoes stdin →
    // stdout, so a round-trip proves the buffer reached the process (the mile the isolated spike showed
    // and this bakes into the suite). A secret-shaped payload also confirms no truncation/encoding loss.
    @Test("input: pipes stdin to the child (round-trips through cat)")
    func pipesStdin() async throws {
        let payload = "github_token = ghp_skilletSyntheticCanaryDoNotUse123456\nsecond line\n"
        let out = try await SubprocessLauncher().run(
            // No limit: this is about what reaches the program's input, and a limit here would only be a
            // guess about how quickly `/bin/cat` runs. The group carries a bound, so a program that never
            // returns fails this check rather than stopping the whole run.
            "/bin/cat", [], input: Data(payload.utf8),
            workingDirectory: nil, timeout: nil, environment: nil, outputLimitBytes: nil)
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
