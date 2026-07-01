import Testing
import Foundation

@Suite("skillet harness", .tags(.integration))
struct HarnessIntegrationTests {
    @Test("harness list shows the replay and claude-code adapters; exit 0")
    func harnessList() async throws {
        let harness = try SkilletHarness()
        let output = try await harness.run(["harness", "list"])
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("replay"))
        #expect(output.stdout.contains("claude-code"))
    }

    @Test("harness info --json carries the schema and per-adapter probe status")
    func harnessInfoJSON() async throws {
        let harness = try SkilletHarness()
        let output = try await harness.run(["harness", "info", "--json"])
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains(#""schema":"skillet.harness-info/1""#))

        let object = try JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [String: Any]
        let adapters = object?["adapters"] as? [[String: Any]]
        #expect(adapters?.contains { ($0["id"] as? String) == "replay" } == true)
        // F6: claude-code ships a real adapter. Its binary isn't installed here, so the real probe
        // reports unavailable with a human "what + why" detail (not a raw enum, not a stub message).
        let claudeCode = adapters?.first { ($0["id"] as? String) == "claude-code" }
        #expect(claudeCode?["available"] as? Bool == false)
        #expect((claudeCode?["detail"] as? String)?.contains("could not find the claude-code binary") == true)
        #expect((claudeCode?["capabilities"] as? [String])?.contains("session_capture") == true)
    }

    @Test("harness info <id> filters to one adapter")
    func harnessInfoFiltered() async throws {
        let harness = try SkilletHarness()
        let output = try await harness.run(["harness", "info", "replay", "--json"])
        #expect(output.exitCode == 0)
        let object = try JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [String: Any]
        let adapters = object?["adapters"] as? [[String: Any]]
        #expect(adapters?.count == 1)
        #expect((adapters?.first?["id"] as? String) == "replay")
    }

    @Test("Unknown harness id is a usage error (exit 2)")
    func unknownHarnessId() async throws {
        let harness = try SkilletHarness()
        let output = try await harness.run(["harness", "info", "bogus-harness"])
        #expect(output.exitCode == 2)
    }

    @Test("harness info shares the strict config loader: an undecodable repo skillet.yaml fails loud (exit 4)")
    func invalidConfigRejected() async throws {
        let root = try Fixture.makeProject(); defer { Fixture.remove(root) }
        try "harness:\n\tclaude-code:\n\t\tpath: /x\n".write(   // tab indentation → invalid YAML
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let output = try await SkilletHarness().run(["harness", "info", "-C", root.path])
        #expect(output.exitCode == 4)
    }

    @Test("An invalid -C directory is an environment error, not silently ignored (exit 3)")
    func invalidDashCRejected() async throws {
        // Previously `harness list` swallowed a bad -C and printed adapters; it must honor the global contract.
        let output = try await SkilletHarness().run(["-C", "/no/such/skillet-dir-xyz", "harness", "list"])
        #expect(output.exitCode == 3)
    }
}
