import Testing
import Foundation

@Suite("Discovery via the binary", .tags(.integration))
struct DiscoveryParityTests {
    @Test("-C parity: resolves the project root from a nested subdirectory")
    func dashCParity() async throws {
        let harness = try SkilletHarness()
        let project = try Fixture.makeProject()
        defer { Fixture.remove(project) }
        let nested = project.appendingPathComponent("a/b/c", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let output = try await harness.run(["-C", nested.path, "--json"])
        #expect(output.exitCode == 0)

        let object = try JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [String: Any]
        let projectObject = object?["project"] as? [String: Any]
        #expect(projectObject?["discovered_via"] as? String == "skillet_yaml")
        // Compare by the fixture's unique directory name (robust to /private symlink resolution).
        let root = (projectObject?["root"] as? String) ?? ""
        #expect(root.hasSuffix(project.lastPathComponent))
    }

    @Test("No project found is benign: root omitted, discovered_via none, exit 0")
    func noProjectBenign() async throws {
        let harness = try SkilletHarness()
        let empty = try Fixture.makeTempDirectory()
        defer { Fixture.remove(empty) }

        let output = try await harness.run(["--json"], workingDirectory: empty)
        #expect(output.exitCode == 0)

        let object = try JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [String: Any]
        let projectObject = object?["project"] as? [String: Any]
        #expect(projectObject?["discovered_via"] as? String == "none")
        #expect(projectObject?["root"] == nil)
    }
}
