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
        let replay = HarnessReplay()
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
        let replay = HarnessReplay() // declares no sessionCapture
        await #expect(throws: HarnessError.self) {
            _ = try await replay.locateSessions(SessionQuery())
        }
    }

    @Test("claude-code stub declares capabilities but is not implemented")
    func claudeCodeStub() async {
        let adapter = ClaudeCodeAdapter()
        #expect(adapter.capabilities.contains(.runTask))
        await #expect(throws: HarnessError.self) { _ = try await adapter.probe() }
    }

    @Test("harness-info report probes the registry and carries the schema")
    func harnessInfoReport() async throws {
        let report = await HarnessInfoReport.build(from: .default)
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
}
