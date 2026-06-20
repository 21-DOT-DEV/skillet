import Testing
import Foundation

@Suite("Root command contract", .tags(.integration))
struct RootContractTests {
    @Test("Bare skillet explains the loop and exits 0")
    func bareExplainsLoop() async throws {
        let harness = try SkilletHarness()
        let project = try Fixture.makeProject()
        defer { Fixture.remove(project) }

        let output = try await harness.run([], workingDirectory: project)
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("skillet"))
        #expect(output.stdout.lowercased().contains("loop"))
    }

    @Test("--json emits a valid skillet.root/1 payload on stdout")
    func jsonRootSchema() async throws {
        let harness = try SkilletHarness()
        let project = try Fixture.makeProject()
        defer { Fixture.remove(project) }

        let output = try await harness.run(["--json"], workingDirectory: project)
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains(#""schema":"skillet.root/1""#))

        let object = try JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [String: Any]
        #expect(object?["schema"] as? String == "skillet.root/1")
        #expect(object?["skillet_version"] != nil)
    }
}
