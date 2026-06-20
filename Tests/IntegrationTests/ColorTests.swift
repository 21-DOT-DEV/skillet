import Testing
import Foundation

@Suite("Color via the binary", .tags(.integration))
struct ColorTests {
    @Test("--color never produces no ANSI escapes")
    func neverNoANSI() async throws {
        let harness = try SkilletHarness()
        let project = try Fixture.makeProject()
        defer { Fixture.remove(project) }

        let output = try await harness.run(["--color", "never"], workingDirectory: project)
        #expect(output.exitCode == 0)
        #expect(!output.stdout.contains("\u{1B}["))
    }

    @Test("--color always emits ANSI escapes")
    func alwaysANSI() async throws {
        let harness = try SkilletHarness()
        let project = try Fixture.makeProject()
        defer { Fixture.remove(project) }

        let output = try await harness.run(["--color", "always"], workingDirectory: project)
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("\u{1B}["))
    }
}
