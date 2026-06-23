import Testing
import Foundation
import EDDCore
import HarnessKit

@Suite("claude-code skill visibility")
struct VisibilityTests {
    @Test("Passes when SKILL.md resolves under the skill directory")
    func visible() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-vis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "# skill".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        try ClaudeCodeAdapter().verifySkillVisibility(SkillRef(name: "demo", path: dir.path), strategy: .discoveryPath)
    }

    @Test("Throws skillNotVisible when SKILL.md is missing")
    func notVisible() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-vis-missing-\(UUID().uuidString)")
        #expect(throws: EDDError.self) {
            try ClaudeCodeAdapter().verifySkillVisibility(SkillRef(name: "demo", path: dir.path), strategy: .discoveryPath)
        }
    }
}
