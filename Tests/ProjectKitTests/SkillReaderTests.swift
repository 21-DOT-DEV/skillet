import Testing
import Foundation
import ProjectKit

@Suite("Skill source reader")
struct SkillReaderTests {
    /// Build a throwaway `…/skills/demo` directory with a SKILL.md and an optional evals.json.
    /// Returns the skill dir; remove its repo root via `defer`.
    private func makeSkillDir(evals: String?) throws -> (skill: URL, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-reader-\(UUID().uuidString)", isDirectory: true)
        let skill = root.appendingPathComponent("skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\nname: demo\n---\n# demo\n".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        if let evals {
            let evalDir = skill.appendingPathComponent("evaluations", isDirectory: true)
            try FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
            try evals.write(to: evalDir.appendingPathComponent("evals.json"), atomically: true, encoding: .utf8)
        }
        return (skill, root)
    }

    @Test("Reads SKILL.md and a present evals.json")
    func readsWithEvals() throws {
        let (skill, root) = try makeSkillDir(evals: #"{"skill_name":"demo","evals":[]}"#)
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = try SkillReader().read(skillDirectory: skill)
        #expect(raw.name == "demo")
        #expect(raw.markdown.contains("# demo"))
        #expect(raw.evalsJSON != nil)
    }

    @Test("An absent evals.json reads as nil")
    func readsWithoutEvals() throws {
        let (skill, root) = try makeSkillDir(evals: nil)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try SkillReader().read(skillDirectory: skill).evalsJSON == nil)
    }

    @Test("A directory without SKILL.md throws")
    func missingSkillMd() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(throws: (any Error).self) {
            _ = try SkillReader().read(skillDirectory: empty)
        }
    }
}
