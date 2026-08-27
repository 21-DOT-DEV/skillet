import Testing
import EDDCore
import HarnessKit

@Suite("claude-code probe")
struct ProbeTests {
    private func adapter(
        configPath: String? = nil,
        version: String,
        exitCode: Int32 = 0,
        authOutput: ProcessOutput? = nil,
        pathLookup: [String: String] = [:],
        environment: [String: String] = [:]
    ) -> ClaudeCodeAdapter {
        ClaudeCodeAdapter(
            configPath: configPath,
            launcher: FakeLauncher(output: ProcessOutput(stdout: version, stderr: "", exitCode: exitCode), authOutput: authOutput),
            resolver: BinaryResolver(probe: FakeExecutableProbe(pathLookup: pathLookup), environment: environment),
            environment: environment
        )
    }

    @Test("Resolves via PATH and parses the version")
    func resolvesAndParses() async throws {
        let info = try await adapter(version: "2.1.146 (Claude Code)", pathLookup: ["claude": "/usr/bin/claude"]).probe()
        #expect(info.version == "2.1.146")
        #expect(info.available)
    }

    @Test("Not found when no link resolves")
    func notFound() async {
        await #expect(throws: EDDError.self) {
            try await adapter(version: "2.1.146", pathLookup: [:]).probe()
        }
    }

    @Test("A pinned banned version is refused (exit 3)")
    func bannedPinned() async {
        await #expect(throws: EDDError.harnessBanned(harness: "claude-code", version: "2.1.143")) {
            try await adapter(configPath: "/cfg/claude", version: "claude 2.1.143").probe()
        }
    }

    @Test("An auto-discovered banned version surfaces a loud warning, but probe still returns")
    func bannedAuto() async throws {
        let info = try await adapter(version: "2.1.143", pathLookup: ["claude": "/usr/bin/claude"]).probe()
        #expect(info.version == "2.1.143")
        #expect(info.available)
        #expect(info.warnings.contains { $0.contains("2.1.143") && $0.contains("denylist") })
    }

    @Test("A clean auto-discovered version carries no warnings")
    func cleanHasNoWarnings() async throws {
        let info = try await adapter(version: "2.1.146", pathLookup: ["claude": "/usr/bin/claude"]).probe()
        #expect(info.warnings.isEmpty)
    }

    // MARK: - F7 strict preflight (run) + auth status

    @Test("Strict preflight refuses an auto-discovered banned version (run never spends on known-bad)")
    func strictRefusesAutoBanned() async {
        await #expect(throws: EDDError.harnessBanned(harness: "claude-code", version: "2.1.143")) {
            try await adapter(version: "2.1.143", pathLookup: ["claude": "/usr/bin/claude"]).probe(strict: true)
        }
    }

    @Test("probe reports authentication from `claude auth status` (logged-out → authenticated false)")
    func reportsAuthStatus() async throws {
        let loggedOut = ProcessOutput(stdout: #"{"loggedIn":false}"#, stderr: "", exitCode: 1)
        let out = try await adapter(version: "2.1.146", authOutput: loggedOut, pathLookup: ["claude": "/usr/bin/claude"]).probe()
        #expect(!out.authenticated)   // non-strict: reported, not fatal
        #expect(out.available)
        let authed = try await adapter(version: "2.1.146", pathLookup: ["claude": "/usr/bin/claude"]).probe()
        #expect(authed.authenticated) // default fake auth status = logged in
    }

    @Test("Strict preflight refuses an unauthenticated harness (exit 3, before any spend)")
    func strictRefusesUnauthenticated() async {
        let loggedOut = ProcessOutput(stdout: #"{"loggedIn":false}"#, stderr: "", exitCode: 1)
        await #expect(throws: EDDError.harnessUnauthenticated(harness: "claude-code")) {
            try await adapter(version: "2.1.146", authOutput: loggedOut, pathLookup: ["claude": "/usr/bin/claude"]).probe(strict: true)
        }
    }

    @Test("Auth fails closed: exit 0 with unparseable JSON is treated as unauthenticated, not a free pass")
    func authFailsClosedOnMalformed() async throws {
        let malformed = ProcessOutput(stdout: "not json at all", stderr: "", exitCode: 0)
        let info = try await adapter(version: "2.1.146", authOutput: malformed, pathLookup: ["claude": "/usr/bin/claude"]).probe()
        #expect(!info.authenticated)   // non-strict: reported false (was wrongly true before)
        await #expect(throws: EDDError.harnessUnauthenticated(harness: "claude-code")) {
            try await adapter(version: "2.1.146", authOutput: malformed, pathLookup: ["claude": "/usr/bin/claude"]).probe(strict: true)
        }
    }
}

/// **The switch that lets a known-bad version through takes exactly the word it advertises.**
///
/// Some versions of the program this tool drives are known to produce wrong measurements, so they are
/// refused. One environment variable turns that refusal off, and the refusal message tells you to set it
/// to `1`. Any value at all used to do it — including `0`, which is how someone would naturally write
/// "no, leave the check on".
@Suite("Turning off the known-bad-version refusal takes exactly the advertised value")
struct BannedBypassValueTests {
    private func adapter(_ value: String?) -> ClaudeCodeAdapter {
        var environment: [String: String] = ["SKILLET_CLAUDE_CODE_BIN": "/usr/bin/true"]
        if let value { environment["SKILLET_ALLOW_BANNED_CLAUDE_CODE"] = value }
        return ClaudeCodeAdapter(
            launcher: FakeLauncher(output: ProcessOutput(stdout: "9.9.9 (Claude Code)", stderr: "", exitCode: 0)),
            denylist: Denylist(bannedVersions: ["9.9.9"]),
            environment: environment)
    }

    @Test("`1` turns it off, as the message says")
    func oneTurnsItOff() async throws {
        let info = try await adapter("1").probe(strict: false)
        #expect(info.available, "the advertised value was given, so the refusal stands down")
    }

    /// The values that must *not* turn it off. `0` is the one that matters: it reads as "leave the check
    /// on" and used to do the opposite.
    @Test("Anything else leaves it on", arguments: ["0", "", "false", "no", "yes", "true"])
    func anythingElseLeavesItOn(value: String) async {
        await #expect(throws: EDDError.self) { _ = try await adapter(value).probe(strict: false) }
    }

    @Test("Not setting it at all leaves it on")
    func unsetLeavesItOn() async {
        await #expect(throws: EDDError.self) { _ = try await adapter(nil).probe(strict: false) }
    }
}

/// **One environment decides which program is run.**
///
/// The part that works out which program to launch used to be built with its own view of the environment,
/// whatever view the rest of the adapter was given. So a caller naming a program through a variable in a
/// supplied environment was silently ignored and the machine's real environment was consulted instead —
/// two components deciding the same thing from two different sources, agreeing only by coincidence.
@Suite("The program to run is chosen from the environment the adapter was given")
struct AdapterEnvironmentConsistencyTests {
    @Test("A program named in the supplied environment is the one chosen")
    func suppliedEnvironmentIsUsed() async throws {
        let recorder = RecordingLauncher(output: ProcessOutput(stdout: "1.0.0 (Claude Code)", stderr: "", exitCode: 0))
        let adapter = ClaudeCodeAdapter(
            launcher: recorder,
            environment: ["SKILLET_CLAUDE_CODE_BIN": "/tmp/a-named-program"])
        _ = try? await adapter.probe(strict: false)
        #expect(await recorder.executable == "/tmp/a-named-program",
                "the name given to the adapter is the one that reached the launcher")
    }

    /// Passing the resolving part explicitly still wins, for a caller that wants exactly that.
    @Test("An explicitly supplied resolver still overrides")
    func explicitResolverStillWins() async throws {
        let recorder = RecordingLauncher(output: ProcessOutput(stdout: "1.0.0 (Claude Code)", stderr: "", exitCode: 0))
        let adapter = ClaudeCodeAdapter(
            launcher: recorder,
            resolver: BinaryResolver(environment: ["SKILLET_CLAUDE_CODE_BIN": "/tmp/explicit"]),
            environment: ["SKILLET_CLAUDE_CODE_BIN": "/tmp/ignored"])
        _ = try? await adapter.probe(strict: false)
        #expect(await recorder.executable == "/tmp/explicit")
    }
}
