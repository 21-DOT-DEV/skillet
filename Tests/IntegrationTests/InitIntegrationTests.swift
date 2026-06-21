import Testing
import Foundation

@Suite("skillet init", .tags(.integration))
struct InitIntegrationTests {
    @Test("Scaffolds config, self-owned cache ignore, and per-skill evidence dirs; exit 0")
    func initScaffolds() async throws {
        let harness = try SkilletHarness()
        let repo = try Fixture.makeRepoWithSkill("demo")
        defer { Fixture.remove(repo) }

        let out = try await harness.run(["init"], workingDirectory: repo)
        #expect(out.exitCode == 0)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: repo.appendingPathComponent("skillet.yaml").path))
        #expect(fm.fileExists(atPath: repo.appendingPathComponent(".skillet/.gitignore").path))
        for sub in ["friction", "findings", "sessions"] {
            #expect(fm.fileExists(atPath: repo.appendingPathComponent("skills/demo/evaluations/\(sub)").path))
        }
        // self-owned cache ignore; the repo-root .gitignore is never created
        let ignore = try String(contentsOf: repo.appendingPathComponent(".skillet/.gitignore"), encoding: .utf8)
        #expect(ignore.contains("*"))
        #expect(!fm.fileExists(atPath: repo.appendingPathComponent(".gitignore").path))
    }

    @Test("Re-running is idempotent: nothing created, nothing overwritten")
    func idempotent() async throws {
        let harness = try SkilletHarness()
        let repo = try Fixture.makeRepoWithSkill("demo")
        defer { Fixture.remove(repo) }

        _ = try await harness.run(["init"], workingDirectory: repo)
        let yaml = repo.appendingPathComponent("skillet.yaml")
        let before = try String(contentsOf: yaml, encoding: .utf8)

        let out = try await harness.run(["init", "--json"], workingDirectory: repo)
        #expect(out.exitCode == 0)
        let object = try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any]
        #expect((object?["created"] as? [Any])?.isEmpty == true)
        #expect((object?["skipped"] as? [Any])?.isEmpty == false)
        #expect(try String(contentsOf: yaml, encoding: .utf8) == before) // not overwritten
    }

    @Test("--json reports the skillet.init/1 payload with discovered skills")
    func jsonReport() async throws {
        let harness = try SkilletHarness()
        let repo = try Fixture.makeRepoWithSkill("demo")
        defer { Fixture.remove(repo) }

        let out = try await harness.run(["init", "--json"], workingDirectory: repo)
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains(#""schema":"skillet.init/1""#))
        let object = try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any]
        #expect((object?["skills"] as? [String])?.contains("demo") == true)
    }

    @Test("Empty repo initializes config and an empty skills/ root")
    func emptyRepo() async throws {
        let harness = try SkilletHarness()
        let repo = try Fixture.makeTempDirectory()
        defer { Fixture.remove(repo) }

        let out = try await harness.run(["init"], workingDirectory: repo)
        #expect(out.exitCode == 0)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: repo.appendingPathComponent("skillet.yaml").path))
        #expect(fm.fileExists(atPath: repo.appendingPathComponent("skills").path))
    }

    @Test("Nonexistent --skill path is an environment error (exit 3)")
    func badSkillPath() async throws {
        let harness = try SkilletHarness()
        let repo = try Fixture.makeTempDirectory()
        defer { Fixture.remove(repo) }

        let out = try await harness.run(["init", "--skill", "/no/such/skill-xyz"], workingDirectory: repo)
        #expect(out.exitCode == 3)
    }
}
