import Testing
import Foundation
import EDDCore
import TraceKit
@testable import HarnessKit

/// **Which skill a session says it reached for, when nothing was handed to it.**
///
/// One of the things `skillet` measures is *routing*: given a prompt and a shelf of skills, does the
/// model reach for the right one? Nothing is loaded into the session for that measurement — the whole
/// point is that the model chooses. Offline, a stand-in answers instead of a model so tests cost nothing,
/// and it used to report that a skill named `demo` had been reached for, always. So the measurement
/// passed when the skill under test happened to be called `demo` and failed otherwise, on setups that
/// were identical in every other way — and roughly half the tests of that measurement passed only
/// because of the name they had picked.
///
/// A stand-in with an answer baked in is only defensible when it serves a single test; shared across
/// many, it is how a suite goes green for a reason nobody wrote down. The routing answer now comes from
/// the skill's own file — a `replay-fires: true` line, read the same guarded way as the line that tells
/// two versions of a skill apart. **A file that says nothing reaches for nothing**, because reaching for
/// nothing is a real routing outcome and a silent default is exactly how this got in.
///
/// This does not make the offline measurement faithful to a real model — no stand-in can be. It makes it
/// faithful to what the fixture stated, which is what a stand-in is for. Checking the stand-in against a
/// real session is separate work, tracked as `F74` (record a replay file from a live run).
@Suite("The offline stand-in takes routing from the fixture, not from a skill's name")
struct ReplayRoutingTests {
    /// Stages skills the way the routing measurement really stages them: **the frontmatter fence only,
    /// body withheld**. That is deliberate — the measurement asks whether a skill's short description is
    /// enough for a model to reach for it, so handing over the instructions would answer the question
    /// before it was asked. It is also why the declaration has to sit *inside* the fence: written below
    /// it, the staging strips it and every skill silently reaches for nothing. Written this way rather
    /// than as a convenient one-liner precisely so this test cannot pass on a shape the real path never
    /// produces. The full chain, staging included, is covered by the trigger-axis tests a layer up.
    private func stage(_ declarations: [(name: String, fires: Bool)]) throws -> (Workspace, [SkillRef]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-routing-\(UUID().uuidString)", isDirectory: true)
        var refs: [SkillRef] = []
        for skill in declarations {
            let dir = root.appendingPathComponent(".claude/skills/\(skill.name)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let declaration = skill.fires ? "replay-fires: true\n" : ""
            try ("---\nname: \(skill.name)\ndescription: does \(skill.name) things\n\(declaration)---\n"
                 + "\n(stub — body withheld: skillet trigger-axis trial)\n")
                .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            refs.append(SkillRef(name: skill.name, path: dir.path))
        }
        return (Workspace(root: root), refs)
    }

    private func routed(_ workspace: Workspace, _ visible: [SkillRef]) async throws -> [String] {
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: .only(load: [], visible: visible))
        return try adapter.parseTrace(raw).skillInvocations.map(\.skill)
    }

    /// **The name must not be what decides.** Both orderings are run with the same two skills, so a
    /// stand-in that answered by name, by position, or alphabetically fails at least one of them.
    @Test("The skill that declares it is reached for is the one reported, whatever it is called",
          arguments: [("alpha", "beta"), ("beta", "alpha"), ("demo", "tidy-notes"), ("tidy-notes", "demo")])
    func declaredSkillIsReported(chosen: String, other: String) async throws {
        let (workspace, refs) = try stage([(chosen, true), (other, false)])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        #expect(try await routed(workspace, refs) == [chosen])
    }

    /// The fault this closes, stated as its own case: a skill called `demo` used to be reached for
    /// without anything saying so, which is why tests of this measurement passed on the name alone.
    @Test("A skill called `demo` gets no special treatment")
    func demoIsNotSpecial() async throws {
        let (workspace, refs) = try stage([("demo", false)])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        #expect(try await routed(workspace, refs).isEmpty,
                "nothing said this skill would be reached for, so nothing was")
    }

    @Test("When no staged skill says it is reached for, nothing is")
    func silenceReachesForNothing() async throws {
        let (workspace, refs) = try stage([("alpha", false), ("beta", false)])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        #expect(try await routed(workspace, refs).isEmpty)
    }

    /// A session can reach for more than one skill, and the measurement records every one it did — the
    /// skill under test and any other. Collapsing them to a single answer would hide the routing.
    @Test("More than one declaration reports more than one skill")
    func severalDeclarationsAllReported() async throws {
        let (workspace, refs) = try stage([("alpha", true), ("beta", false), ("gamma", true)])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        #expect(try await routed(workspace, refs) == ["alpha", "gamma"])
    }

    @Test("Nothing staged at all reaches for nothing, rather than falling back to a name")
    func emptyShelfReachesForNothing() async throws {
        let (workspace, _) = try stage([])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        #expect(try await routed(workspace, []).isEmpty)
    }

    /// **The other measurement is untouched.** When a skill *is* loaded into the session, it was handed
    /// over rather than chosen, so the session reports it — declaration or not. Only the routing
    /// measurement, where nothing is handed over, reads the declaration.
    @Test("A skill loaded into the session is still reported, with no declaration anywhere")
    func loadedSkillStillReported() async throws {
        let (workspace, refs) = try stage([("alpha", false)])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: .only(load: refs))
        #expect(try adapter.parseTrace(raw).skillInvocations.map(\.skill) == ["alpha"])
    }

    /// **The same rule when no skill is named for the session at all.** A session can be given a list of
    /// skills to consider, or simply be let loose on whatever is staged. Both are the session choosing
    /// for itself, so both must read the declarations — but only the first did. The second kept the
    /// canned answer, so a session answered *as* the staged skill, carrying its marker and its declared
    /// counts, while reporting that a skill called `demo` had been reached for. There was no such skill
    /// staged.
    @Test("With no skill named for the session, the staged declarations still decide", arguments: [
        "tidy-notes", "alpha", "demo"
    ])
    func unnamedSessionReadsDeclarations(name: String) async throws {
        let (workspace, _) = try stage([(name, true)])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: .ambient)
        #expect(try adapter.parseTrace(raw).skillInvocations.map(\.skill) == [name])
    }

    @Test("With no skill named and nothing declaring, nothing is reached for")
    func unnamedSessionSilenceReachesForNothing() async throws {
        let (workspace, _) = try stage([("tidy-notes", false)])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: .ambient)
        #expect(try adapter.parseTrace(raw).skillInvocations.isEmpty,
                "nothing said it would be reached for — and `demo` is not staged at all")
    }

    /// The three things a session reports about a staged skill must agree about *which* skill it is
    /// talking about. They were resolved by three separate readers, and one disagreed.
    @Test("What the session says it used, what it answered as, and what it counted all name one skill")
    func allThreeReadersAgree() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-agree-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent(".claude/skills/tidy-notes", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: tidy-notes\nreplay-fires: true\n---\nreplay-marker: v2\nreplay-tokens: 1 2 3 4\n"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let adapter = ReplayAdapter()
        let workspace = Workspace(root: root)
        let trace = try adapter.parseTrace(
            try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: .ambient))
        #expect(trace.skillInvocations.map(\.skill) == ["tidy-notes"], "the skill it says it used")
        #expect(trace.turns.contains { $0.text.contains("v2") }, "the version it answered as")
        #expect(trace.usage?.total == 10, "and the counts that skill stated")
    }

    /// **Every skill handed to the session is named, not just the first.** Every place in the program
    /// hands over exactly one, so nothing was wrong today — but the real thing this stands in for takes as
    /// many as it is given, so the two disagreed about what the input means and a second skill would have
    /// gone unreported with nothing saying so.
    @Test("A session handed several skills names all of them")
    func severalLoadedSkillsAllNamed() async throws {
        let (workspace, refs) = try stage([("alpha", false), ("beta", false), ("gamma", false)])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: .only(load: refs))
        #expect(try adapter.parseTrace(raw).skillInvocations.map(\.skill) == ["alpha", "beta", "gamma"],
                "handed over, so reported — declarations do not enter into it")
    }

    @Test("A run deliberately without any skill still reaches for nothing")
    func skillFreeRunReachesForNothing() async throws {
        let (workspace, _) = try stage([("alpha", true)])
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: SkillSet.none)
        #expect(try adapter.parseTrace(raw).skillInvocations.isEmpty,
                "a declaration must not leak into the arm that is measured without the skill")
    }
}
/// **The skill under test is read before its siblings.**
///
/// The stand-in looks for a declaration in each staged skill and takes the first it finds. Which one comes
/// first therefore decides whose declaration is read — and a review asked whether a sibling's could be
/// picked up instead of the target's. It cannot, when there is a target: the loaded skill is put ahead of
/// the rest. Pinned here because it is a guarantee the readers depend on, and nothing was checking that
/// the two lists stayed in that order.
@Suite("The skill under test is read before its siblings")
struct CandidateOrderTests {
    @Test("A loaded skill comes before the merely-visible ones")
    func loadedComesFirst() {
        let target = SkillRef(name: "target", path: "/tmp/target")
        let siblings = [SkillRef(name: "alpha", path: "/tmp/alpha"), SkillRef(name: "zulu", path: "/tmp/zulu")]
        let names = ReplayAdapter.candidateNames(
            in: Workspace(root: URL(fileURLWithPath: "/tmp/ws")),
            skill: .only(load: [target], visible: siblings))
        #expect(names.first == "target",
                "alphabetically 'alpha' would win; the skill under test must be read first: \(names)")
    }
}
