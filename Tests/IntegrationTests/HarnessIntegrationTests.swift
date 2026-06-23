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
}
