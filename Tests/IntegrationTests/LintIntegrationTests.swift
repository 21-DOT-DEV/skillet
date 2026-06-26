import Testing
import Foundation

@Suite("skillet lint via the binary", .tags(.integration))
struct LintIntegrationTests {
    @Test("A clean skill lints to exit 0")
    func cleanExitsZero() async throws {
        let root = try Fixture.makeLintRepo(description: "short and clear", evals: 3)
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["lint", "-C", root.path])
        #expect(out.exitCode == 0)
    }

    @Test("Error-tier findings exit 1 with their ids present")
    func badExitsOne() async throws {
        let root = try Fixture.makeLintRepo(description: String(repeating: "a", count: 1100), evals: nil)
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["lint", "-C", root.path, "--color", "never"])
        #expect(out.exitCode == 1)
        #expect(out.stdout.contains("SKILL-L001"))   // over-long description
        #expect(out.stdout.contains("SKILL-L009"))   // missing evals
    }

    @Test("--json carries skillet.lint/1 and the tier tallies")
    func jsonSchema() async throws {
        let root = try Fixture.makeLintRepo(description: String(repeating: "a", count: 1100), evals: nil)
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["lint", "-C", root.path, "--json"])
        #expect(out.exitCode == 1)
        #expect(out.stdout.contains(#""schema":"skillet.lint/1""#))
        #expect(out.stdout.contains(#""errors":2"#))
    }

    @Test("A <3-case evals.json warns but still exits 0")
    func shortEvalsWarns() async throws {
        let root = try Fixture.makeLintRepo(description: "ok", evals: 1)
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["lint", "-C", root.path, "--color", "never"])
        #expect(out.exitCode == 0)               // warn-only → success
        #expect(out.stdout.contains("SKILL-L009"))
    }

    @Test("An unknown skill argument is a usage error (exit 2)")
    func unknownSkill() async throws {
        let root = try Fixture.makeLintRepo(description: "ok", evals: 3)
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["lint", "nonesuch", "-C", root.path])
        #expect(out.exitCode == 2)
    }

    @Test("Selecting a skill by name lints only that skill")
    func nameSelection() async throws {
        let root = try Fixture.makeLintRepo(skill: "good", description: "fine", evals: 3)   // clean
        defer { Fixture.remove(root) }
        // Add a deliberately-broken sibling skill.
        let bad = root.appendingPathComponent("skills/bad", isDirectory: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try "---\nname: bad\ndescription: \(String(repeating: "a", count: 1100))\n---\n# bad\n"
            .write(to: bad.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // Linting only "good" passes despite the broken sibling; linting "bad" fails.
        #expect(try await SkilletHarness().run(["lint", "good", "-C", root.path]).exitCode == 0)
        #expect(try await SkilletHarness().run(["lint", "bad", "-C", root.path]).exitCode == 1)
    }
}
