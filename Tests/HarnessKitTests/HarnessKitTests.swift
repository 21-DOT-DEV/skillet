import Testing
import Foundation
import EDDCore
import TraceKit
import HarnessKit

@Suite("Harness adapter seam")
struct HarnessKitTests {
    @Test("Capabilities expose stable snake_case names")
    func capabilityNames() {
        let caps: HarnessCapabilities = [.runTask, .traceParsing]
        #expect(caps.names == ["run_task", "trace_parsing"])
    }

    @Test("Replay double probes and parses a canned Trace through the protocol")
    func replayProvesTheSeam() async throws {
        let replay = ReplayAdapter()
        let info = try await replay.probe()
        #expect(info.available)
        #expect(info.id == "replay")

        let raw = try await replay.run(TaskSpec(query: "hi"), in: Workspace(root: URL(fileURLWithPath: "/tmp")), skills: .none)
        let trace = try replay.parseTrace(raw)
        #expect(trace.harness == "replay")
        #expect(trace.turns.count == 2)
    }

    @Test("Unsupported capabilities degrade loudly")
    func unsupportedThrows() async {
        let replay = ReplayAdapter() // declares no sessionCapture
        await #expect(throws: HarnessError.self) {
            _ = try await replay.locateSessions(SessionQuery())
        }
    }

    @Test("claude-code ships a real adapter; run() remains the F7 seam")
    func claudeCodeRunSeam() async {
        let adapter = ClaudeCodeAdapter()
        #expect(adapter.capabilities.contains(.runTask))
        await #expect(throws: HarnessError.self) {
            _ = try await adapter.run(TaskSpec(query: "hi"), in: Workspace(root: URL(fileURLWithPath: "/tmp")), skills: .none)
        }
    }

    @Test("harness-info report probes adapters and carries the schema")
    func harnessInfoReport() async throws {
        // Inject a claude-code that resolves nothing → deterministically unavailable (no real binary here).
        let claude = ClaudeCodeAdapter(
            launcher: FakeLauncher(output: ProcessOutput(stdout: "", stderr: "", exitCode: 1)),
            resolver: BinaryResolver(probe: FakeExecutableProbe(), environment: [:]),
            environment: [:]
        )
        let report = await HarnessInfoReport.build(from: HarnessRegistry(adapters: [ReplayAdapter(), claude]))
        let ids = report.adapters.map(\.id)
        #expect(ids.contains("replay"))
        #expect(ids.contains("claude-code"))

        let replay = report.adapters.first { $0.id == "replay" }
        #expect(replay?.available == true)
        let claudeCode = report.adapters.first { $0.id == "claude-code" }
        #expect(claudeCode?.available == false)
        #expect(claudeCode?.detail != nil)

        let json = try SkilletJSON.encode(report)
        #expect(json.contains(#""schema":"skillet.harness-info/1""#))
    }

    @Test("the default registry includes replay and claude-code")
    func defaultRegistry() {
        let ids = HarnessRegistry.default.adapters.map(\.id)
        #expect(ids.contains("replay"))
        #expect(ids.contains("claude-code"))
    }
}
