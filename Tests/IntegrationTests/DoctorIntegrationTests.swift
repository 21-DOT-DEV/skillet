import Testing
import Foundation

/// `skillet doctor` against the built binary — the F3 contract: exit 0 with warnings allowed,
/// exit 3 + remedy on any failure row, shared 2/4 classes for usage/corrupt-config, and the
/// frozen `skillet.doctor/1` `--json` payload. A shim `claude` binary makes probes hermetic.
@Suite("doctor integration", .tags(.integration))
struct DoctorIntegrationTests {

    /// A fake `claude` that answers `--version` and `auth status --json` — probes without a real CLI.
    private func makeShim(loggedIn: Bool = true, dir: URL) throws -> String {
        let shim = dir.appendingPathComponent("claude-shim.sh")
        let script = """
        #!/bin/sh
        case "$1" in
          --version) echo "9.9.9 (Claude Code)" ;;
          auth) echo '{"loggedIn":\(loggedIn)}' ;;
          *) exit 1 ;;
        esac
        """
        try script.write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        return shim.path
    }

    @Test("Healthy project: exit 0, ✓ rows, config origin reported")
    func healthy() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim]
        )
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("doctor: ready"))
        #expect(out.stdout.contains("loaded"))          // config origin row
        #expect(out.stdout.contains("9.9.9"))           // harness version row
        #expect(out.stdout.contains("→ next: skillet run demo"))
    }

    @Test("--json emits the frozen skillet.doctor/1 payload")
    func json() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "--json", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim]
        )
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains(#""schema":"skillet.doctor/1""#))
        #expect(out.stdout.contains(#""healthy":true"#))
        #expect(out.stdout.contains(#""check":"skill.visibility""#))
        // Presence-guaranteed: a clean lint still emits its row (absent id = check didn't run).
        #expect(out.stdout.contains(#""check":"skill.lint""#))
    }

    @Test("Unauthenticated is a warning, never a failure (run owns the refusal)")
    func unauthenticatedWarns() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        let shim = try makeShim(loggedIn: false, dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim]
        )
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("not authenticated"))
    }

    @Test("Unresolvable harness binary: exit 3 with a remedy line")
    func missingBinary() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": "/nonexistent/claude"]
        )
        #expect(out.exitCode == 3)
        #expect(out.stdout.contains("fix:"))
    }

    @Test("Error-tier lint finding fails doctor (exit 3), surfacing the rule id")
    func lintErrorFails() async throws {
        let root = try Fixture.makeLintRepo(description: String(repeating: "x", count: 1100))
        defer { Fixture.remove(root) }
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim]
        )
        #expect(out.exitCode == 3)
        #expect(out.stdout.contains("SKILL-L001"))
    }

    @Test("A symlinked reference fails visibility with the dropped path named")
    func symlinkedReferenceFails() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        let skill = root.appendingPathComponent("skills/demo")
        try FileManager.default.createDirectory(at: skill.appendingPathComponent("references"), withIntermediateDirectories: true)
        try "ref".write(to: skill.appendingPathComponent("references/ok.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: skill.appendingPathComponent("references/link.md"),
            withDestinationURL: skill.appendingPathComponent("references/ok.md")
        )
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim]
        )
        #expect(out.exitCode == 3)
        #expect(out.stdout.contains("references/link.md"))
    }

    @Test("A symlinked SKILL.md and a symlinked reference surface in one pass")
    func bothVisibilityIssuesOnePass() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        let skill = root.appendingPathComponent("skills/demo")
        try FileManager.default.createDirectory(at: skill.appendingPathComponent("references"), withIntermediateDirectories: true)
        try "ref".write(to: skill.appendingPathComponent("references/ok.md"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: skill.appendingPathComponent("SKILL.md"))
        try FileManager.default.createSymbolicLink(
            at: skill.appendingPathComponent("SKILL.md"),
            withDestinationURL: skill.appendingPathComponent("references/ok.md")
        )
        try FileManager.default.createSymbolicLink(
            at: skill.appendingPathComponent("references/link.md"),
            withDestinationURL: skill.appendingPathComponent("references/ok.md")
        )
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim]
        )
        #expect(out.exitCode == 3)
        #expect(out.stdout.contains("SKILL.md is a symlink"))     // both issues in the same run,
        #expect(out.stdout.contains("references/link.md"))        // never fix-one-rerun-discover-next
    }

    @Test("Corrupt skillet.yaml stays the shared artifact class (exit 4)")
    func corruptConfig() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        try "{{{{ not yaml".write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["doctor", "-C", root.path])
        #expect(out.exitCode == 4)
    }

    @Test("Zero skills: healthy exit 0; authoring suggestion honors skills_root")
    func zeroSkillsHonorsSkillsRoot() async throws {
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }
        try "project:\n  skills_root: custom-skills\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8
        )
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim]
        )
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("custom-skills/<name>/"))   // config is the source of truth
    }

    @Test("Every failure row in the JSON payload carries a remedy (frozen invariant)")
    func failureRowsAlwaysCarryRemedy() async throws {
        // Multi-failure fixture: missing binary + symlinked reference + lint error, in one run.
        let root = try Fixture.makeLintRepo(description: String(repeating: "x", count: 1100))
        defer { Fixture.remove(root) }
        let skill = root.appendingPathComponent("skills/demo")
        try FileManager.default.createDirectory(at: skill.appendingPathComponent("references"), withIntermediateDirectories: true)
        try "ref".write(to: skill.appendingPathComponent("references/ok.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: skill.appendingPathComponent("references/link.md"),
            withDestinationURL: skill.appendingPathComponent("references/ok.md")
        )
        let out = try await SkilletHarness().run(
            ["doctor", "--json", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": "/nonexistent/claude"]
        )
        #expect(out.exitCode == 3)
        struct Payload: Decodable {
            struct Row: Decodable { let status: String; let remedy: String? }
            let rows: [Row]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(out.stdout.utf8))
        let failures = payload.rows.filter { $0.status == "failure" }
        #expect(failures.count >= 3)
        #expect(failures.allSatisfy { !($0.remedy ?? "").isEmpty })
    }

    @Test("Unknown skill name stays the shared usage class (exit 2)")
    func unknownSkill() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "nope", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim]
        )
        #expect(out.exitCode == 2)
    }
}
