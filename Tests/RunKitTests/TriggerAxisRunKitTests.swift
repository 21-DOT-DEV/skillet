import Testing
import Foundation
import EDDCore
import HarnessKit
import JudgeKit
import RunKit

@Suite("Trigger axis — stub staging + deterministic loop (F14)")
struct TriggerAxisRunKitTests {
    private func makeSkill(_ name: String, in base: URL, frontmatter: Bool = true) throws -> SkillRef {
        let dir = base.appendingPathComponent("skills/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let markdown = frontmatter
            ? "---\nname: \(name)\ndescription: does \(name) things\n---\n# Body\nsecret body content\n"
            : "# no fence at all\n"
        try markdown.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return SkillRef(name: name, path: dir.path)
    }

    @Test("frontmatterStub keeps the fence verbatim and withholds the body")
    func stubExtraction() {
        let stub = WorkspaceManager.frontmatterStub(markdown: "---\nname: x\ndescription: d\n---\nBody line.\n")
        #expect(stub?.hasPrefix("---\nname: x\ndescription: d\n---") == true)
        #expect(stub?.contains("Body line.") == false)
        #expect(stub?.contains("stub — body withheld") == true)
        #expect(WorkspaceManager.frontmatterStub(markdown: "# no fence\n") == nil)
        // CRLF files must stage too — the YAML frontmatter parser accepts them, so a lint-clean
        // skill must never silently fail to stub (review round 1, finding 3).
        #expect(WorkspaceManager.frontmatterStub(markdown: "---\r\nname: x\r\ndescription: d\r\n---\r\nBody\r\n") != nil)
    }

    @Test("A target that fails to stage records infra-failed trials — never a false near-miss pass")
    func skippedTargetNeverMeasures() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-trig-skip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let broken = try makeSkill("broken", in: base, frontmatter: false)   // fence-less → won't stage
        let sibling = try makeSkill("sibling", in: base)

        let runner = Runner(adapter: ReplayAdapter(), judge: ReplayJudge([:], defaultPass: true))
        let results = await runner.runTrigger(
            target: broken, corpus: [broken, sibling],
            cases: [(id: "trigger-0", query: "near miss", shouldTrigger: false)],
            k: 2, base: base.appendingPathComponent("cache")
        )
        // Without the guard this would be exit .passed + firedTarget=false → a FALSE PASS for the
        // near-miss. Infra-failed trials can never count as passes.
        #expect(results[0].trials.allSatisfy { $0.exit == .failed })
        #expect(results[0].passes == 0)
    }

    @Test("prepareTrigger stages every corpus skill as a stub; unstageable siblings are skipped, named")
    func corpusStaging() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-trig-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let a = try makeSkill("alpha", in: base)
        let b = try makeSkill("beta", in: base)
        let broken = try makeSkill("gamma", in: base, frontmatter: false)   // fence-less → skipped

        let staging = try WorkspaceManager().prepareTrigger(corpus: [a, b, broken], base: base, label: "ws")
        defer { try? WorkspaceManager().destroy(staging.workspace) }
        #expect(staging.staged == ["alpha", "beta"])
        #expect(staging.skipped == ["gamma"])
        let alphaStub = try String(contentsOf: staging.workspace.root.appendingPathComponent(".claude/skills/alpha/SKILL.md"), encoding: .utf8)
        #expect(alphaStub.contains("description: does alpha things"))
        #expect(!alphaStub.contains("secret body content"))   // bodies withheld (§9.2)
    }

    @Test("A symlinked sibling skill FOLDER is skipped, never staged from outside the repo")
    func symlinkedSiblingSkipped() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("skillet-trig-sym-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let real = try makeSkill("real", in: base)
        // An out-of-tree skill reachable only through a symlinked folder — discovery doesn't filter
        // these, so staging must (review round 4, finding 3).
        let outside = base.appendingPathComponent("outside/evil", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try "---\nname: evil\ndescription: out-of-repo content\n---\nBody.\n"
            .write(to: outside.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let link = base.appendingPathComponent("skills/evil")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)

        let staging = try WorkspaceManager().prepareTrigger(
            corpus: [real, SkillRef(name: "evil", path: link.path)], base: base, label: "ws"
        )
        defer { try? WorkspaceManager().destroy(staging.workspace) }
        #expect(staging.staged == ["real"])
        #expect(staging.skipped == ["evil"])
        #expect(!fm.fileExists(atPath: staging.workspace.root.appendingPathComponent(".claude/skills/evil/SKILL.md").path))
    }

    @Test("runTrigger judges fired/not-fired deterministically from skillInvocations (replay)")
    func deterministicLoop() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-trig-loop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let demo = try makeSkill("demo", in: base)          // the canned trace fires "demo"
        let other = try makeSkill("other", in: base)

        let runner = Runner(adapter: ReplayAdapter(), judge: ReplayJudge([:], defaultPass: true))
        let results = await runner.runTrigger(
            target: demo, corpus: [demo, other],
            cases: [
                (id: "trigger-0", query: "should fire", shouldTrigger: true),     // fires → PASS
                (id: "trigger-1", query: "near miss", shouldTrigger: false)       // fires → FAIL
            ],
            k: 2, base: base.appendingPathComponent("cache")
        )
        #expect(results.count == 2)
        #expect(results[0].passes == 2)
        #expect(results[1].passes == 0)

        // Attribution (D-3): for a target the canned trace does NOT fire, firedOther carries the routing.
        let missed = await runner.runTrigger(
            target: other, corpus: [demo, other],
            cases: [(id: "trigger-0", query: "routed", shouldTrigger: false)],
            k: 1, base: base.appendingPathComponent("cache2")
        )
        #expect(missed[0].passes == 1)                          // correct non-fire for `other`
        #expect(missed[0].trials[0].firedOther == ["demo"])     // routing recorded
    }
}
