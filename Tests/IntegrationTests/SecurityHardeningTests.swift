import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// F33 security pass: hang-class regressions at the binary level. A FIFO planted where a default
/// command path reads a repo file used to block the process forever (its `open()` has no
/// `O_NONBLOCK`); the safe-read helper refuses on a pre-open `stat`, so these commands must now exit
/// fast with a clear reason. If one of these tests hangs, the guard ordering regressed.
@Suite("untrusted-repo file hardening via the binary", .tags(.integration))
struct SecurityHardeningTests {
    @Test("A FIFO skillet.yaml no longer hangs every command — artifact error, fast")
    func fifoConfigRefused() async throws {
        let root = try Fixture.makeRepoWithSkill()
        defer { Fixture.remove(root) }
        #expect(mkfifo(root.appendingPathComponent("skillet.yaml").path, 0o644) == 0)
        let out = try await SkilletHarness().run(["-C", root.path, "lint"])
        #expect(out.exitCode == 4)                                   // artifact class, like undecodable config
        #expect(out.stderr.contains("not a regular file"))
    }

    @Test("A FIFO SKILL.md no longer hangs lint — environment error, fast")
    func fifoSkillMDRefused() async throws {
        let root = try Fixture.makeProject()
        defer { Fixture.remove(root) }
        let skill = root.appendingPathComponent("skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        #expect(mkfifo(skill.appendingPathComponent("SKILL.md").path, 0o644) == 0)
        let out = try await SkilletHarness().run(["-C", root.path, "lint"])
        #expect(out.exitCode != 0)                                   // refused, not hung
        #expect((out.stderr + out.stdout).contains("not a regular file"))
    }

    @Test("A hostile skills_root is rejected at config load for every command — nothing enumerated (round 10)")
    func hostileSkillsRootRejectedEverywhere() async throws {
        // Round 10 (T8 fixed): `skills_root: ../../..` used to make skill discovery LIST directories
        // outside the project before per-command confinement threw. The accept-known-good rule at the
        // shared config seam now rejects the value for lint/doctor/run/triage/capture alike.
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }
        try "project:\n  skills_root: \"../../..\"\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        for command in [["lint"], ["triage"], ["doctor"]] {
            let out = try await SkilletHarness().run(["-C", root.path] + command)
            #expect(out.exitCode == 4, "\(command) should refuse the config as an artifact error")
            #expect(out.stderr.contains("skills_root"), "\(command) should name the offending value")
        }
    }

    /// Writes `skills_root: <value>` into an existing fixture repo.
    private func setSkillsRoot(_ value: String, in root: URL) throws {
        try "project:\n  skills_root: \"\(value)\"\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
    }

    /// One spelling of the setting that names where skill folders live, and the clean path it must
    /// print. Rows rather than a run of near-identical blocks: this test started with one spelling and
    /// gained another each time one turned up, so the next is now a line rather than another copy of
    /// set-run-assert — and each row runs as its own case, so a failure names **which** spelling broke.
    struct Spelling: Sendable, CustomStringConvertible {
        let value: String
        let mustNotShow: String
        let why: String
        var description: String { "skills_root: '\(value)'" }
    }

    static let spellings: [Spelling] = [
        .init(value: "skills/", mustNotShow: "skills//",
              why: "a trailing separator must not double up"),
        .init(value: "skills /", mustNotShow: "skills /",
              why: "a space before the separator survives a whole-value trim, so each piece needs trimming too"),
        .init(value: "./skills", mustNotShow: "./skills/demo",
              why: "a leading './' is the same defect in another costume"),
        .init(value: "skills/ /", mustNotShow: "skills/ ",
              why: "a piece that is nothing but a space — trimming empties it and an empty piece is dropped, the only spelling reaching both steps together")
    ]

    /// The "review findings under …" hint. It needs a recorded session, or the command takes the
    /// empty-corpus branch ("record a session — …"), which never mentions the setting at all.
    ///
    /// Every row asserts something POSITIVE — the clean path must appear — so undoing the cleanup fails
    /// this. A row that only said "the bad spelling is absent" would pass even if nothing were printed,
    /// which is exactly how the first version of this test was wrong.
    @Test("Every spelling of skills_root prints the same clean path", arguments: spellings)
    func skillsRootCanonicalizedInPrintedPaths(_ spelling: Spelling) async throws {
        let version = try await TriageIntegrationTests.currentVersion()
        let root = try TriageIntegrationTests.makeTriageRepo(
            bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }

        try setSkillsRoot(spelling.value, in: root)
        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.stdout.contains("skills/demo/evaluations/findings/"),
                "must print the clean path — \(spelling.why)")
        #expect(!out.stdout.contains(spelling.mustNotShow), "the raw spelling leaked into the printed path")
    }

    /// The other place the setting is pasted into a printed line, shown when nothing is discovered.
    /// Kept separate rather than forced into the rows above: different setup, different assertion.
    @Test("The 'add a skill' hint uses the cleaned-up skills_root too")
    func skillsRootCanonicalizedInTheAddASkillHint() async throws {
        let bare = try Fixture.makeTempDirectory()
        defer { Fixture.remove(bare) }
        try setSkillsRoot("skills/", in: bare)
        let noSkills = try await SkilletHarness().run(["-C", bare.path, "triage"])
        #expect(noSkills.stdout.contains("skills/<name>/SKILL.md"))
        #expect(!noSkills.stdout.contains("skills//<name>"))
    }

    @Test("Canonicalizing skills_root keeps the escape guard intact and preserves the conventional '.' value")
    func skillsRootCanonicalizationPreservesGuardsAndConvention() async throws {
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }

        // The leading "/" is preserved on purpose: collapsing it would turn "/etc/" into a relative-looking
        // "etc" and defeat the rule that keeps skills_root inside the project.
        try setSkillsRoot("/etc/", in: root)
        let absolute = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(absolute.exitCode == 4)
        #expect(absolute.stderr.contains("absolute"))

        // All-whitespace is an unambiguous typo: trimming makes it empty, which the existing rule refuses.
        try setSkillsRoot("   ", in: root)
        let blank = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(blank.exitCode == 4)
        #expect(blank.stderr.contains("empty"))

        // "." is the ecosystem's conventional "the directory holding this config" (TypeScript's `rootDir`
        // and friends) — a deliberate value, unlike a blank one. It must keep working: silently turning an
        // accepted value into an error is a breaking change, not a bug fix.
        let demo = root.appendingPathComponent("demo", isDirectory: true)
        try FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: skills living at the project root\n---\nBody.\n"
            .write(to: demo.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try setSkillsRoot(".", in: root)
        let dotRoot = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(dotRoot.exitCode != 4, "a lone '.' is a conventional value, not a config error")
        #expect(!dotRoot.stderr.contains("skills_root"))
        // **And the skill is actually found.** Checking only that nothing was rejected cannot tell
        // "this works" from "this silently discovered nothing" — a change that quietly ignored the value
        // would have passed. The rule is written at the top of this file and was not applied here.
        #expect(dotRoot.stdout.contains("demo") || dotRoot.stderr.contains("demo"),
                "the skill sitting at the project root must be discovered, not just tolerated")

        // The escape guard is SEGMENT-wise: a folder whose NAME merely contains dots is not an escape.
        // Only the unit tests covered this, so nothing proved the whole command agreed with the rule —
        // and a guard that over-refuses locks people out of a legal folder name.
        let dotted = root.appendingPathComponent("my..skills", isDirectory: true)
        try FileManager.default.createDirectory(at: dotted, withIntermediateDirectories: true)
        try setSkillsRoot("my..skills", in: root)
        let dottedName = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(dottedName.exitCode != 4, "'my..skills' is a folder name, not a '..' escape")
        #expect(!dottedName.stderr.contains("path segment"))
        // Same gap, ten lines apart and written in the same breath: not being refused is not the same as
        // being used. The folder must appear in a path the command prints.
        #expect(dottedName.stdout.contains("my..skills") || dottedName.stderr.contains("my..skills"),
                "the folder whose name merely contains dots must actually be used, not just permitted")
    }

    @Test("A hard-linked skillet.yaml is refused (linked inode, not followed)")
    func hardLinkedConfigRefused() async throws {
        let root = try Fixture.makeRepoWithSkill()
        defer { Fixture.remove(root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: outside) }
        try "project:\n  skills_root: skills\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.linkItem(at: outside, to: root.appendingPathComponent("skillet.yaml"))
        let out = try await SkilletHarness().run(["-C", root.path, "lint"])
        #expect(out.exitCode == 4)
        #expect(out.stderr.contains("hard link"))
    }

    @Test("A multi-part skills location works end to end — nested folders are not treated as one name")
    func multiSegmentSkillsRootResolves() async throws {
        // Verified behaviour, pinned: appending "foo/bar" to the project folder yields a nested path, so
        // keeping multi-part values through cleanup is correct. Without this test, a future switch to a
        // single-segment call would silently break every project that nests its skills.
        let root = try Fixture.makeTempDirectory(); defer { Fixture.remove(root) }
        try "project:\n  skills_root: \"nested/skills\"\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let demo = root.appendingPathComponent("nested/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a skill living in a nested skills folder, long enough for lint.\n---\nBody.\n"
            .write(to: demo.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(["-C", root.path, "lint"])
        // The property under test is DISCOVERY, not a clean bill of health: this fixture has no evals
        // file, so the free checks legitimately complain. What matters is that the nested skill was
        // found at all — if the two parts were collapsed into one folder name, nothing would be.
        #expect(out.stdout.contains("demo"), "the skill in a nested location must be discovered")
        #expect(!(out.stdout + out.stderr).contains("no skills found"))
        // And the printed path keeps both parts rather than collapsing them.
        // With no recordings the command takes a different branch and never prints a path, so the
        // escape clause this assertion used to carry meant the path was usually not checked at all.
        // Give it a recording, so the branch under test is the one that runs.
        let sessions = root.appendingPathComponent("nested/skills/demo/evaluations/sessions",
                                                   isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let version = try await TriageIntegrationTests.currentVersion()
        try #"{"id": "2026-06-01-a", "skill": "demo", "skill_version": "1.0.0", "model": "opus", "harness": "claude-code", "captured_at": "2026-06-01T00:00:00Z", "schema_version": 2}"#
            .write(to: sessions.appendingPathComponent("2026-06-01-a.session-meta.json"),
                   atomically: true, encoding: .utf8)
        try #"{"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "skillet", "version": "\#(version)"}}, "results": [{"ruleId": "SKILL-S001", "level": "warning", "message": {"text": "m"}}]}]}"#
            .write(to: sessions.appendingPathComponent("2026-06-01-a.audit-input.sarif"),
                   atomically: true, encoding: .utf8)
        let triage = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(!triage.stdout.contains("record a session"), "precondition: a recording exists")
        #expect(triage.stdout.contains("nested/skills/demo/evaluations/findings/"),
                "the printed path must keep both parts of a multi-segment skills root")
    }
}
