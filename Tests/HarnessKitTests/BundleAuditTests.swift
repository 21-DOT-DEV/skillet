import Testing
import Foundation
import EDDCore
import HarnessKit

/// The F3 positive-load audit: what the run stager would silently drop must be loud here.
@Suite("SkillBundleAudit — staging-filter parity")
struct BundleAuditTests {
    private func makeSkill() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("references"), withIntermediateDirectories: true
        )
        try "# demo".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "ref".write(to: dir.appendingPathComponent("references/ok.md"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test("A clean bundle is visible: no offenders, no drops")
    func cleanBundle() throws {
        let dir = try makeSkill()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = SkillBundleAudit.audit(skillDirectory: dir)
        #expect(result.isVisible)
        #expect(result.skillMDIssue == nil)
        #expect(result.symlinks.isEmpty)
        #expect(result.droppedHidden.isEmpty)
    }

    @Test("Missing SKILL.md is the SKILL.md issue")
    func missingSkillMD() throws {
        let dir = try makeSkill()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.removeItem(at: dir.appendingPathComponent("SKILL.md"))
        let result = SkillBundleAudit.audit(skillDirectory: dir)
        #expect(!result.isVisible)
        #expect(result.skillMDIssue?.contains("no SKILL.md") == true)
    }

    @Test("A symlinked SKILL.md is refused (run rejects it; staging would drop it)")
    func symlinkedSkillMD() throws {
        let dir = try makeSkill()
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("references/ok.md")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("SKILL.md"))
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("SKILL.md"), withDestinationURL: real)
        let result = SkillBundleAudit.audit(skillDirectory: dir)
        #expect(!result.isVisible)
        #expect(result.skillMDIssue?.contains("symlink") == true)
    }

    @Test("A symlink inside references/ is an offender named by relative path")
    func symlinkedReference() throws {
        let dir = try makeSkill()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("references/link.md"),
            withDestinationURL: dir.appendingPathComponent("references/ok.md")
        )
        let result = SkillBundleAudit.audit(skillDirectory: dir)
        #expect(!result.isVisible)
        #expect(result.symlinks == ["references/link.md"])
    }

    @Test("Hidden entries are warnings (policy drops), not offenders")
    func hiddenEntries() throws {
        let dir = try makeSkill()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("references/.hidden.md"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        let result = SkillBundleAudit.audit(skillDirectory: dir)
        #expect(result.isVisible)
        #expect(result.droppedHidden == [".DS_Store", "references/.hidden.md"])
    }

    @Test("The private evaluations/ namespace is never audited")
    func evaluationsIgnored() throws {
        let dir = try makeSkill()
        defer { try? FileManager.default.removeItem(at: dir) }
        let evals = dir.appendingPathComponent("evaluations")
        try FileManager.default.createDirectory(at: evals, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: evals.appendingPathComponent("link.json"),
            withDestinationURL: dir.appendingPathComponent("references/ok.md")
        )
        let result = SkillBundleAudit.audit(skillDirectory: dir)
        #expect(result.isVisible)
        #expect(result.symlinks.isEmpty)
    }

    @Test("Reports a symlinked SKILL.md and dropped references together (one pass)")
    func bothIssuesTogether() throws {
        let dir = try makeSkill()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.removeItem(at: dir.appendingPathComponent("SKILL.md"))
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("SKILL.md"),
            withDestinationURL: dir.appendingPathComponent("references/ok.md")
        )
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("references/link.md"),
            withDestinationURL: dir.appendingPathComponent("references/ok.md")
        )
        let result = SkillBundleAudit.audit(skillDirectory: dir)
        #expect(result.skillMDIssue?.contains("symlink") == true)
        // The top-level SKILL.md symlink is also a dropped bundle entry — both findings, one audit.
        #expect(result.symlinks == ["SKILL.md", "references/link.md"])
        #expect(!result.isVisible)
    }

    @Test("verifySkillVisibility throws skillNotVisible naming the dropped symlinks")
    func adapterThrowsWithPaths() throws {
        let dir = try makeSkill()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("references/link.md"),
            withDestinationURL: dir.appendingPathComponent("references/ok.md")
        )
        do {
            try ClaudeCodeAdapter().verifySkillVisibility(SkillRef(name: "demo", path: dir.path), strategy: .discoveryPath)
            Issue.record("expected skillNotVisible")
        } catch let error as EDDError {
            guard case let .skillNotVisible(skill, reason) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(skill == "demo")
            #expect(reason.contains("references/link.md"))
        }
    }
}
