import Testing
import Foundation
import HarnessKit
import RunKit

/// Guards the F3 audit ↔ F7 stager rule parity (Specs/008 §7 risk): whatever `WorkspaceManager`
/// silently drops (symlinks + hidden at any depth, the `evaluations/` namespace) is exactly what
/// `SkillBundleAudit` flags — so a green `doctor` visibility row means a complete staged bundle.
@Suite("SkillBundleAudit ↔ WorkspaceManager staging parity")
struct StagingParityTests {
    @Test("The audit flags exactly what staging drops")
    func parity() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("skillet-parity-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        let skill = base.appendingPathComponent("skills/demo", isDirectory: true)
        try fm.createDirectory(at: skill.appendingPathComponent("references"), withIntermediateDirectories: true)
        try fm.createDirectory(at: skill.appendingPathComponent("evaluations"), withIntermediateDirectories: true)
        try "# demo".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "ref".write(to: skill.appendingPathComponent("references/ok.md"), atomically: true, encoding: .utf8)
        try "hide".write(to: skill.appendingPathComponent("references/.hidden.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: skill.appendingPathComponent("evaluations/evals.json"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(
            at: skill.appendingPathComponent("references/link.md"),
            withDestinationURL: skill.appendingPathComponent("references/ok.md")
        )

        let audit = SkillBundleAudit.audit(skillDirectory: skill)
        #expect(audit.symlinks == ["references/link.md"])
        #expect(audit.droppedHidden == ["references/.hidden.md"])
        #expect(audit.skillMDIssue == nil)

        let workspace = try WorkspaceManager().prepare(
            skill: SkillRef(name: "demo", path: skill.path),
            files: [],
            base: base.appendingPathComponent("ws"),
            label: "trial"
        )
        defer { try? WorkspaceManager().destroy(workspace) }
        let staged = workspace.root.appendingPathComponent(".claude/skills/demo")

        // Staged: the regular files. Dropped: exactly the audit's symlink + hidden findings, plus
        // the private evaluations/ namespace.
        #expect(fm.fileExists(atPath: staged.appendingPathComponent("SKILL.md").path))
        #expect(fm.fileExists(atPath: staged.appendingPathComponent("references/ok.md").path))
        for dropped in audit.symlinks + audit.droppedHidden {
            #expect(!fm.fileExists(atPath: staged.appendingPathComponent(dropped).path), "staging should drop \(dropped)")
        }
        #expect(!fm.fileExists(atPath: staged.appendingPathComponent("evaluations").path))
    }
}
