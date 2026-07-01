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
