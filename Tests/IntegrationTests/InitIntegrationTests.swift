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
        // The emitted template surfaces the F7 defaults so users see the new controls (round-9 review).
        let yaml = try String(contentsOf: repo.appendingPathComponent("skillet.yaml"), encoding: .utf8)
        #expect(yaml.contains("max_output_bytes: 67108864"))
        #expect(yaml.contains("provider: claude-code"))
        #expect(fm.fileExists(atPath: repo.appendingPathComponent(".skillet/.gitignore").path))
        for sub in ["friction", "findings", "sessions"] {
            #expect(fm.fileExists(atPath: repo.appendingPathComponent("skills/demo/evaluations/\(sub)").path))
        }
        // The design-promised skeletons (closed in F14 review round 5): empty, so they skip their
        // axis rather than block, and never overwrite user content.
        let evals = try String(contentsOf: repo.appendingPathComponent("skills/demo/evaluations/evals.json"), encoding: .utf8)
        #expect(evals.contains(#""skill_name":"demo""#))
        #expect(evals.contains(#""evals":[]"#))
        let trigger = try String(contentsOf: repo.appendingPathComponent("skills/demo/evaluations/trigger-eval.json"), encoding: .utf8)
        #expect(trigger.trimmingCharacters(in: .whitespacesAndNewlines) == "[]")
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
        // User content in a scaffolded skeleton must survive a re-init untouched.
        let evalsURL = repo.appendingPathComponent("skills/demo/evaluations/evals.json")
        try #"{"skill_name":"demo","evals":[{"id":"mine","prompt":"p","expectations":["x"]}]}"#
            .write(to: evalsURL, atomically: true, encoding: .utf8)

        let out = try await harness.run(["init", "--json"], workingDirectory: repo)
        #expect(out.exitCode == 0)
        let object = try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any]
        #expect((object?["created"] as? [Any])?.isEmpty == true)
        #expect((object?["skipped"] as? [Any])?.isEmpty == false)
        #expect(try String(contentsOf: yaml, encoding: .utf8) == before) // not overwritten
        #expect(try String(contentsOf: evalsURL, encoding: .utf8).contains(#""id":"mine""#)) // skeleton never clobbers
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
