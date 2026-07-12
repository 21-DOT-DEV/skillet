import Foundation
import Testing

/// Drives `skillet capture` through the built binary to lock in the path-traversal guards (F26/F32).
/// The sessions dir (`<skills_root>/<skill>/evaluations/sessions`) is a *write* destination, so an
/// escape via `--skill` or a config `skills_root` would let a bundle be written outside the project.
/// Both guards fire *before* any session lookup or scanner run, so these tests need neither a native
/// session store nor `betterleaks` on `PATH`.
@Suite("skillet capture path-traversal guards")
struct CaptureIntegrationTests {

    @Test("--skill with `..` segments is rejected up front (exit 2), before project/session/scanner work")
    func hostileSkillRejected() async throws {
        // Hermetic temp cwd (no project): the `--skill` allowlist runs before project discovery, so a
        // regression would fall through to `projectNotFound` (exit 3) — not this exit-2 usage error.
        let dir = try Fixture.makeTempDirectory(); defer { Fixture.remove(dir) }
        let out = try await SkilletHarness().run(["capture", "--skill", "../../etc", "--slug", "x"], workingDirectory: dir)
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("invalid --skill"))
    }

    @Test("A --skill containing a slash is rejected, so it can't become a nested path component")
    func slashSkillRejected() async throws {
        let dir = try Fixture.makeTempDirectory(); defer { Fixture.remove(dir) }
        let out = try await SkilletHarness().run(["capture", "--skill", "a/b", "--slug", "x"], workingDirectory: dir)
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("invalid --skill"))
    }

    @Test("A non-ASCII --slug (combining diacritic) is rejected — the documented ASCII contract")
    func nonAsciiSlugRejected() async throws {
        let dir = try Fixture.makeTempDirectory(); defer { Fixture.remove(dir) }
        let out = try await SkilletHarness().run(["capture", "--skill", "demo", "--slug", "a\u{0301}bc"], workingDirectory: dir)
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("invalid --slug"))
    }

    @Test("--target-dir escaping the project is rejected (exit 2)")
    func targetDirEscapeRejected() async throws {
        let root = try Fixture.makeTempDirectory(); defer { Fixture.remove(root) }
        try "project:\n  skills_root: skills\n".write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["capture", "--skill", "demo", "--slug", "x", "--target-dir", "/etc"], workingDirectory: root)
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("--target-dir must be inside the project"))
    }

    @Test("--skill accepts non-slug directory names (My_Skill.v2) but still rejects traversal")
    func skillNameAcceptsDirNames() async throws {
        let dir = try Fixture.makeTempDirectory(); defer { Fixture.remove(dir) }
        // Non-slug but a safe single component → passes skill validation (later fails at project discovery,
        // exit 3 — NOT exit-2 "invalid --skill"). Matches SkillScanner/run, which accept any SKILL.md dir.
        let ok = try await SkilletHarness().run(["capture", "--skill", "My_Skill.v2", "--slug", "x"], workingDirectory: dir)
        #expect(!ok.stderr.contains("invalid --skill"))
        let bad = try await SkilletHarness().run(["capture", "--skill", "../evil", "--slug", "x"], workingDirectory: dir)
        #expect(bad.exitCode == 2 && bad.stderr.contains("invalid --skill"))
    }

    @Test("--date rejects an impossible date (2026-99-99), accepts a real one")
    func invalidDateRejected() async throws {
        let dir = try Fixture.makeTempDirectory(); defer { Fixture.remove(dir) }
        let bad = try await SkilletHarness().run(["capture", "--skill", "demo", "--slug", "x", "--date", "2026-99-99"], workingDirectory: dir)
        #expect(bad.exitCode == 2 && bad.stderr.contains("invalid --date"))
        let good = try await SkilletHarness().run(["capture", "--skill", "demo", "--slug", "x", "--date", "2026-02-28"], workingDirectory: dir)
        #expect(!good.stderr.contains("invalid --date"))   // valid date → past validation (project-not-found later)
    }

    @Test("A malicious skills_root in config can't escape the project root (defense in depth, exit 2)")
    func hostileSkillsRootRejected() async throws {
        // A discoverable project (`skillet.yaml`) whose skills_root climbs out of the repo. `--skill` is
        // valid, so this exercises the second layer: the canonicalize-under-projectRoot assertion.
        let root = try Fixture.makeTempDirectory(); defer { Fixture.remove(root) }
        try "project:\n  skills_root: \"../../..\"\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["capture", "--skill", "demo", "--slug", "x"], workingDirectory: root)
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("outside the project") && out.stderr.contains("escapes"))
    }
}
