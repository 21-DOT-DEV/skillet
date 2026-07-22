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
