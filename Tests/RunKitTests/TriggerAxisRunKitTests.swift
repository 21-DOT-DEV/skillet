import Testing
import Foundation
import EDDCore
import HarnessKit
import JudgeKit
import RunKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("Trigger axis — stub staging + deterministic loop (F14)")
struct TriggerAxisRunKitTests {
    /// `fires` states, in the skill's own frontmatter, that the offline stand-in should report this skill
    /// as the one reached for. It has to sit inside the fence: staging for this measurement keeps the
    /// fence and withholds the body, so a line written below it never reaches the stand-in. Before this
    /// existed the stand-in always reported a skill named `demo`, so these tests passed on the name they
    /// happened to pick rather than on anything they stated.
    private func makeSkill(_ name: String, in base: URL, frontmatter: Bool = true,
                           fires: Bool = false) throws -> SkillRef {
        let dir = base.appendingPathComponent("skills/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let declaration = fires ? "replay-fires: true\n" : ""
        let markdown = frontmatter
            ? "---\nname: \(name)\ndescription: does \(name) things\n\(declaration)---\n# Body\nsecret body content\n"
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

    @Test("A target that fails to stage records ungraded attempts — never a false near-miss pass")
    func skippedTargetNeverMeasures() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-trig-skip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let broken = try makeSkill("broken", in: base, frontmatter: false)   // fence-less → won't stage
        let sibling = try makeSkill("sibling", in: base)

        let runner = Runner(adapter: ReplayAdapter(), judge: ReplayJudge([:], defaultPass: true))
        let results = await runner.runTrigger(
            target: broken, corpus: [broken, sibling], skillsRoot: base.appendingPathComponent("skills"),
            cases: [(id: "trigger-0", query: "near miss", shouldTrigger: false)],
            k: 2, base: base.appendingPathComponent("cache")
        )
        // Without the guard this would be exit .passed + firedTarget=false → a FALSE PASS for the
        // near-miss. An attempt that never ran can never count as a pass — and, since it measured
        // nothing about the skill, it must not count as a failure of the skill either. This test asserted
        // the latter while its own name called the attempts infrastructure failures.
        #expect(results[0].trials.allSatisfy { $0.exit == .error })
        #expect(results[0].passes == 0)
        #expect(results[0].measured == 0, "nothing was measured, so nothing counts toward a score")
    }

    @Test("prepareTrigger stages every corpus skill as a stub; unstageable siblings are skipped, named")
    func corpusStaging() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-trig-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let a = try makeSkill("alpha", in: base)
        let b = try makeSkill("beta", in: base)
        let broken = try makeSkill("gamma", in: base, frontmatter: false)   // fence-less → skipped

        let staging = try WorkspaceManager().prepareTrigger(corpus: [a, b, broken], skillsRoot: base.appendingPathComponent("skills"), base: base, label: "ws")
        defer { try? WorkspaceManager().destroy(staging.workspace) }
        #expect(staging.staged == ["alpha", "beta"])
        #expect(staging.skipped == ["gamma"])
        let alphaStub = try String(contentsOf: staging.workspace.root.appendingPathComponent(".claude/skills/alpha/SKILL.md"), encoding: .utf8)
        #expect(alphaStub.contains("description: does alpha things"))
        #expect(!alphaStub.contains("secret body content"))   // bodies withheld (§9.2)
    }

    @Test("A FIFO SKILL.md is skipped instantly, never read (round 11 — the per-trial TOCTOU window)")
    func fifoSkillMDSkipped() throws {
        // Staging runs per trial, AFTER the once-per-run safe-read preflight — a SKILL.md swapped for
        // a FIFO in that window hung the old unguarded read forever. The safe reader refuses on a
        // pre-open stat, so this test HANGS if the guard ordering ever regresses.
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("skillet-trig-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let good = try makeSkill("alpha", in: base)
        let trap = try makeSkill("trap", in: base)
        let trapMD = URL(fileURLWithPath: trap.path).appendingPathComponent("SKILL.md")
        try FileManager.default.removeItem(at: trapMD)
        #expect(mkfifo(trapMD.path, 0o644) == 0)

        let staging = try WorkspaceManager().prepareTrigger(corpus: [good, trap], skillsRoot: base.appendingPathComponent("skills"), base: base, label: "ws-fifo")
        defer { try? WorkspaceManager().destroy(staging.workspace) }
        #expect(staging.staged == ["alpha"])
        #expect(staging.skipped == ["trap"])
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
            corpus: [real, SkillRef(name: "evil", path: link.path)],
            skillsRoot: base.appendingPathComponent("skills"), base: base, label: "ws"
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
        // `demo` states in its own file that it is the one reached for; `other` states nothing. The
        // names are now incidental — this used to work only because the stand-in reported "demo".
        let demo = try makeSkill("demo", in: base, fires: true)
        let other = try makeSkill("other", in: base)

        let runner = Runner(adapter: ReplayAdapter(), judge: ReplayJudge([:], defaultPass: true))
        let results = await runner.runTrigger(
            target: demo, corpus: [demo, other], skillsRoot: base.appendingPathComponent("skills"),
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
            target: other, corpus: [demo, other], skillsRoot: base.appendingPathComponent("skills"),
            cases: [(id: "trigger-0", query: "routed", shouldTrigger: false)],
            k: 1, base: base.appendingPathComponent("cache2")
        )
        #expect(missed[0].passes == 1)                          // correct non-fire for `other`
        #expect(missed[0].trials[0].firedOther == ["demo"])     // routing recorded
    }
}

/// **A shortcut planted on a folder partway along the path is refused, not followed.**
///
/// A *shortcut* is a file entry that silently points somewhere else. When this tool measures whether a
/// model reaches for the right skill, it copies each candidate skill's opening description into a scratch
/// folder and shows it to the model. If a shortcut on any folder in the path were followed, whatever it
/// pointed at would be copied in and shown instead — content from outside the project entirely.
///
/// The reader used before refused a shortcut only at the very last step of the path, so a shortcut on a
/// folder above the file was followed. The gap is catalogued as `CWE-59` ("link following"). This runs
/// once per attempt rather than once per run, so a check done at start-up cannot keep it true — a folder
/// can be swapped in between.
@Suite("Staging refuses a shortcut anywhere on the path, not only at the end")
struct TriggerStagingConfinementTests {
    @Test("A skill reached through a shortcut folder is skipped, and nothing outside is staged")
    func shortcutFolderOnPathIsRefused() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("skillet-conf-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        let skillsRoot = base.appendingPathComponent("skills", isDirectory: true)

        // A real skill, staged normally, so the test can tell "refused this one" from "refused everything".
        let honest = skillsRoot.appendingPathComponent("honest", isDirectory: true)
        try fm.createDirectory(at: honest, withIntermediateDirectories: true)
        try "---\nname: honest\ndescription: an ordinary skill\n---\nbody\n"
            .write(to: honest.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // Content outside the project, and a folder inside it that points at that content's parent — so
        // the skill folder itself is genuine and only a folder *above* the file is the shortcut.
        let outside = base.appendingPathComponent("elsewhere/smuggled", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try "---\nname: smuggled\ndescription: content from outside the project\n---\nsecret\n"
            .write(to: outside.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let hop = skillsRoot.appendingPathComponent("hop", isDirectory: true)
        try fm.createSymbolicLink(at: hop, withDestinationURL: base.appendingPathComponent("elsewhere", isDirectory: true))

        let staging = try WorkspaceManager().prepareTrigger(
            corpus: [SkillRef(name: "honest", path: honest.path),
                     SkillRef(name: "smuggled", path: hop.appendingPathComponent("smuggled").path)],
            skillsRoot: skillsRoot, base: base, label: "ws")
        defer { try? WorkspaceManager().destroy(staging.workspace) }

        #expect(staging.staged == ["honest"], "the ordinary skill still stages, so this is not a blanket refusal")
        #expect(staging.skipped == ["smuggled"], "and the one reached through a shortcut is named as skipped")
        let shown = staging.workspace.root.appendingPathComponent(".claude/skills/smuggled/SKILL.md")
        #expect(!fm.fileExists(atPath: shown.path), "nothing from outside the project was copied in")
    }
}
