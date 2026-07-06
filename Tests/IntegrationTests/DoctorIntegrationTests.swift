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

    @Test("A trigger-only skill (no evals.json) warns instead of failing — doctor predicts the runner")
    func triggerOnlySkillWarns() async throws {
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }
        try "project:\n  skills_root: skills\n".write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let dir = root.appendingPathComponent("skills/demo/evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a trigger-only demo skill\n---\nBody.\n"
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        try #"[{"query":"fire","should_trigger":true}]"#
            .write(to: dir.appendingPathComponent("trigger-eval.json"), atomically: true, encoding: .utf8)
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim]
        )
        #expect(out.exitCode == 0)                       // since F14, `run` accepts this skill
        #expect(out.stdout.contains("SKILL-L009"))       // the finding still shows — as a warning
    }

    @Test("A broken or empty trigger-eval.json does NOT soften the has-evals failure (round 2)")
    func brokenTriggerEvalsKeepFailure() async throws {
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }
        try "project:\n  skills_root: skills\n".write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let dir = root.appendingPathComponent("skills/demo/evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a demo skill\n---\nBody.\n"
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        let shim = try makeShim(dir: root)

        // Corrupt file: run would exit 4 — doctor must not report healthy.
        try "{not an array}".write(to: dir.appendingPathComponent("trigger-eval.json"), atomically: true, encoding: .utf8)
        let corrupt = try await SkilletHarness().run(["doctor", "-C", root.path], environment: ["SKILLET_CLAUDE_CODE_BIN": shim])
        #expect(corrupt.exitCode == 3)
        #expect(corrupt.stdout.contains("invalid, empty, or symlinked"))

        // Empty array: nothing would run — the failure must stand too.
        try "[]".write(to: dir.appendingPathComponent("trigger-eval.json"), atomically: true, encoding: .utf8)
        let empty = try await SkilletHarness().run(["doctor", "-C", root.path], environment: ["SKILLET_CLAUDE_CODE_BIN": shim])
        #expect(empty.exitCode == 3)
    }

    @Test("DANGLING symlinks are never 'absent': trigger and evals variants both keep doctor red (round 6)")
    func danglingSymlinksNeverAbsent() async throws {
        // Variant A: valid evals + dangling trigger-file symlink → run refuses it, doctor must too.
        let rootA = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(rootA) }
        try FileManager.default.createSymbolicLink(
            at: rootA.appendingPathComponent("skills/demo/evaluations/trigger-eval.json"),
            withDestinationURL: rootA.appendingPathComponent("does-not-exist.json")
        )
        let shimA = try makeShim(dir: rootA)
        let outA = try await SkilletHarness().run(["doctor", "-C", rootA.path], environment: ["SKILLET_CLAUDE_CODE_BIN": shimA])
        #expect(outA.exitCode == 3)
        #expect(outA.stdout.contains("symlink"))

        // Variant B: dangling evals-file symlink + usable trigger → no leniency; failure stands.
        let rootB = try Fixture.makeTempDirectory()
        defer { Fixture.remove(rootB) }
        try "project:\n  skills_root: skills\n".write(to: rootB.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let dirB = rootB.appendingPathComponent("skills/demo/evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a demo skill\n---\nBody.\n"
            .write(to: rootB.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        try #"[{"query":"fire","should_trigger":true}]"#
            .write(to: dirB.appendingPathComponent("trigger-eval.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: dirB.appendingPathComponent("evals.json"),
            withDestinationURL: rootB.appendingPathComponent("nowhere.json")
        )
        let shimB = try makeShim(dir: rootB)
        let outB = try await SkilletHarness().run(["doctor", "-C", rootB.path], environment: ["SKILLET_CLAUDE_CODE_BIN": shimB])
        #expect(outB.exitCode == 3)
    }

    @Test("EMPTY evals.json + usable trigger file: doctor's green now matches the runner (round 5)")
    func emptyEvalsUsableTriggerHealthy() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description", evals: 0)
        defer { Fixture.remove(root) }
        try #"[{"query":"fire","should_trigger":true}]"#.write(
            to: root.appendingPathComponent("skills/demo/evaluations/trigger-eval.json"),
            atomically: true, encoding: .utf8
        )
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(["doctor", "-C", root.path], environment: ["SKILLET_CLAUDE_CODE_BIN": shim])
        // Default `run` now skips the empty behavioral axis and runs trigger — green is TRUE here.
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("SKILL-L009"))   // still visible, as the warning it is
    }

    @Test("VALID evals + malformed trigger file: the dedicated trigger row fails doctor (round 4)")
    func validEvalsMalformedTriggerFails() async throws {
        // With valid behavioral evals there is no has-evals finding to hang this on — the dedicated
        // trigger-evals row must catch it, because default `run` refuses the file with exit 4.
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        try "{not an array}".write(
            to: root.appendingPathComponent("skills/demo/evaluations/trigger-eval.json"),
            atomically: true, encoding: .utf8
        )
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(["doctor", "-C", root.path], environment: ["SKILLET_CLAUDE_CODE_BIN": shim])
        #expect(out.exitCode == 3)
        #expect(out.stdout.contains("skill.trigger-evals"))
        #expect(out.stdout.contains("will refuse it"))
    }

    @Test("Usable trigger file + CORRUPT evals.json keeps doctor failing (run would exit 4)")
    func corruptEvalsKeepsFailureDespiteTrigger() async throws {
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }
        try "project:\n  skills_root: skills\n".write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let dir = root.appendingPathComponent("skills/demo/evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a demo skill\n---\nBody.\n"
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        try "{corrupt json".write(to: dir.appendingPathComponent("evals.json"), atomically: true, encoding: .utf8)
        try #"[{"query":"fire","should_trigger":true}]"#
            .write(to: dir.appendingPathComponent("trigger-eval.json"), atomically: true, encoding: .utf8)
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(["doctor", "-C", root.path], environment: ["SKILLET_CLAUDE_CODE_BIN": shim])
        // Default `run` loads the present evals.json and refuses corrupt JSON before any trigger
        // trial — so a green doctor here would be a false prediction (round 3, P1a).
        #expect(out.exitCode == 3)
        #expect(out.stdout.contains("not valid JSON"))
    }

    @Test("A SYMLINKED trigger file never earns the downgrade (run refuses symlinked read paths)")
    func symlinkedTriggerKeepsFailure() async throws {
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }
        try "project:\n  skills_root: skills\n".write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let dir = root.appendingPathComponent("skills/demo/evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a demo skill\n---\nBody.\n"
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        // Valid trigger content — but reached through a symlink, which the runner refuses to follow.
        try #"[{"query":"fire","should_trigger":true}]"#
            .write(to: root.appendingPathComponent("real-trigger.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("trigger-eval.json"),
            withDestinationURL: root.appendingPathComponent("real-trigger.json")
        )
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(["doctor", "-C", root.path], environment: ["SKILLET_CLAUDE_CODE_BIN": shim])
        #expect(out.exitCode == 3)
        #expect(out.stdout.contains("symlinked"))
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
