import Testing
import EDDCore
import HarnessKit

@Suite("claude-code probe")
struct ProbeTests {
    private func adapter(
        configPath: String? = nil,
        version: String,
        exitCode: Int32 = 0,
        pathLookup: [String: String] = [:],
        environment: [String: String] = [:]
    ) -> ClaudeCodeAdapter {
        ClaudeCodeAdapter(
            configPath: configPath,
            launcher: FakeLauncher(output: ProcessOutput(stdout: version, stderr: "", exitCode: exitCode)),
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

    @Test("An auto-discovered banned version warns + falls back (probe still returns)")
    func bannedAuto() async throws {
        let info = try await adapter(version: "2.1.143", pathLookup: ["claude": "/usr/bin/claude"]).probe()
        #expect(info.version == "2.1.143")
    }
}
