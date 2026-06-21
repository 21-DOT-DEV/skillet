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
}
