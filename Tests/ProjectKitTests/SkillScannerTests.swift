import Testing
import Foundation
import ProjectKit

@Suite("Skill discovery")
struct SkillScannerTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("Finds immediate subdirectories that contain SKILL.md, sorted")
    func findsSkills() {
        var probe = InMemoryProbe()
        probe.entries = [
            "/repo/skills": ["docc-articles", "swift-yaml", "notes"],
            "/repo/skills/docc-articles": ["SKILL.md"],
            "/repo/skills/swift-yaml": ["SKILL.md"],
            "/repo/skills/notes": ["README.md"] // not a skill
        ]
        probe.readableDirectories = [
            "/repo/skills/docc-articles", "/repo/skills/swift-yaml", "/repo/skills/notes"
        ]
        let skills = SkillScanner(probe: probe).scan(skillsRoot: url("/repo/skills"))
        #expect(skills.map(\.lastPathComponent) == ["docc-articles", "swift-yaml"])
    }

    @Test("Explicit paths keep only those containing SKILL.md")
    func explicitPaths() {
        var probe = InMemoryProbe()
        probe.entries = ["/a": ["SKILL.md"], "/b": ["nope.txt"]]
        let kept = SkillScanner(probe: probe).explicit([url("/a"), url("/b")])
        #expect(kept.map(\.lastPathComponent) == ["a"])
    }

    @Test("A symlinked skills-root is never followed — no skills, no enumeration outside the project (round 14)")
    func symlinkedSkillsRootRefused() throws {
        // Real FileSystemProbe: discovery runs before any per-command confinement check, so a
        // `skills -> /elsewhere` symlink must not enumerate the target on any platform (macOS returns
        // [] here already; Linux Foundation may follow — the guard makes it deterministic).
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("myskill"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: real.appendingPathComponent("myskill/SKILL.md"))
        let symlinkedRoot = base.appendingPathComponent("skills")
        try FileManager.default.createSymbolicLink(at: symlinkedRoot, withDestinationURL: real)

        #expect(SkillScanner().scan(skillsRoot: symlinkedRoot).isEmpty)                                   // symlinked root → nothing
        #expect(SkillScanner().scan(skillsRoot: real).map(\.lastPathComponent) == ["myskill"])           // real root → the skill
    }
}

/// **A skill folder that is a link is not walked into.**
///
/// Only the folder holding the skills was refused, not an individual skill inside it. So a link there
/// pointing anywhere on the machine was read and reported on by the commands that merely inspect a skill,
/// while the commands that run or edit one refused the same folder — two halves of the tool disagreeing
/// about what counts as a skill, and a way to have files from outside the project read and described.
///
/// Declining is what every tool that walks directories does by default: measured, `find`, `ripgrep` and
/// `git` all leave directory links alone unless explicitly asked otherwise.
@Suite("A skill folder that is a link is not discovered")
struct LinkedSkillFolderTests {
    @Test("A link inside the skills folder is not treated as a skill")
    func linkedSkillIsNotDiscovered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let skills = root.appendingPathComponent("skills")
        let outside = root.appendingPathComponent("elsewhere")
        for dir in [skills.appendingPathComponent("real"), outside] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\nname: x\n---\n".write(to: dir.appendingPathComponent("SKILL.md"),
                                            atomically: true, encoding: .utf8)
        }
        try FileManager.default.createSymbolicLink(at: skills.appendingPathComponent("linked"),
                                                   withDestinationURL: outside)

        // **The directory listing is supplied, not read from this machine.** Read from this machine, the
        // link is already left out — a link to a folder is not reported as a folder here — so a test
        // using the real listing passes whether or not this code filters anything, and proves nothing.
        // That is the point of the fix: the exclusion was the platform's, not this code's, and this
        // project builds for another platform whose listing is a separate implementation. The reader
        // below reports the link as a folder, which is what that other behaviour looks like.
        let listing = ListingThatReportsLinksAsFolders(entries: [skills.appendingPathComponent("real"),
                                                                skills.appendingPathComponent("linked")])
        let found = SkillScanner(probe: listing).scan(skillsRoot: skills).map(\.lastPathComponent)
        #expect(found == ["real"], "the ordinary skill is found and the link is not: \(found)")
    }
}

/// Reports every entry it was given, including links — the behaviour this code must not depend on being
/// absent.
private struct ListingThatReportsLinksAsFolders: DirectoryProbe {
    let entries: [URL]
    func exists(named name: String, in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }
    func isReadableDirectory(_ url: URL) -> Bool { true }
    func subdirectories(of directory: URL) -> [URL] { entries }
}
