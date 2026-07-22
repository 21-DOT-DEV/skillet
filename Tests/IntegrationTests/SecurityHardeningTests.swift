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
}
