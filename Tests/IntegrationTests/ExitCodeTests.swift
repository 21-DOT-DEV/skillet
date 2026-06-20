import Testing
import Foundation

@Suite("Exit codes via the binary", .tags(.integration))
struct ExitCodeTests {
    @Test("Unknown command is a usage error (exit 2)")
    func unknownCommand() async throws {
        let harness = try SkilletHarness()
        let output = try await harness.run(["bogus-not-a-command"])
        #expect(output.exitCode == 2)
    }

    @Test("Unknown flag is a usage error (exit 2)")
    func unknownFlag() async throws {
        let harness = try SkilletHarness()
        let output = try await harness.run(["--definitely-not-a-flag"])
        #expect(output.exitCode == 2)
    }

    @Test("-C to a nonexistent directory is an environment error (exit 3) with a JSON error on stderr")
    func dashCNonexistentJSON() async throws {
        let harness = try SkilletHarness()
        let output = try await harness.run(["-C", "/no/such/dir/skillet-xyz", "--json"])
        #expect(output.exitCode == 3)
        #expect(output.stderr.contains(#""schema":"skillet.error/1""#))
        #expect(output.stderr.contains(#""code":3"#))
        #expect(output.stdout.isEmpty)
    }

    @Test("-C nonexistent in human mode prints what/why/fix to stderr (exit 3)")
    func dashCNonexistentHuman() async throws {
        let harness = try SkilletHarness()
        let output = try await harness.run(["-C", "/no/such/dir/skillet-xyz"])
        #expect(output.exitCode == 3)
        #expect(output.stderr.contains("error:"))
        #expect(output.stderr.contains("fix:"))
    }

    @Test("--help exits 0")
    func helpExitsZero() async throws {
        let harness = try SkilletHarness()
        let output = try await harness.run(["--help"])
        #expect(output.exitCode == 0)
    }
}
