import Testing
import Foundation
import EDDCore
import TraceKit
import HarnessKit

@Suite("Harness adapter seam")
struct HarnessKitTests {
    @Test("Capabilities expose stable snake_case names")
    func capabilityNames() {
        let caps: HarnessCapabilities = [.runTask, .traceParsing]
        #expect(caps.names == ["run_task", "trace_parsing"])
    }

    @Test("Replay double probes and parses a canned Trace through the protocol")
    func replayProvesTheSeam() async throws {
        let replay = ReplayAdapter()
        let info = try await replay.probe()
        #expect(info.available)
        #expect(info.id == "replay")

        let raw = try await replay.run(TaskSpec(query: "hi"), in: Workspace(root: URL(fileURLWithPath: "/tmp")), skills: .none)
        let trace = try replay.parseTrace(raw)
        #expect(trace.harness == "replay")
        #expect(trace.turns.count == 2)
    }

    @Test("Unsupported capabilities degrade loudly")
    func unsupportedThrows() async {
        let replay = ReplayAdapter() // declares no sessionCapture
        await #expect(throws: HarnessError.self) {
            _ = try await replay.locateSessions(SessionQuery())
        }
    }

    @Test("claude-code run() is wired (F7): it executes through the launcher and returns a RawTrace")
    func claudeCodeRunWired() async throws {
        let adapter = ClaudeCodeAdapter(
            launcher: FakeLauncher(output: ProcessOutput(stdout: "{}", stderr: "", exitCode: 0)),
            resolver: BinaryResolver(probe: FakeExecutableProbe(pathLookup: ["claude": "/usr/bin/claude"]), environment: [:]),
            environment: [:]
        )
        #expect(adapter.capabilities.contains(.runTask))
        // No longer the notImplemented seam — run() now executes and returns the harness's output.
        let raw = try await adapter.run(TaskSpec(query: "hi"), in: Workspace(root: URL(fileURLWithPath: "/tmp")), skills: .none)
        #expect(raw.harness == "claude-code")
    }

    @Test("harness-info report probes adapters and carries the schema")
    func harnessInfoReport() async throws {
        // Inject a claude-code that resolves nothing → deterministically unavailable (no real binary here).
        let claude = ClaudeCodeAdapter(
            launcher: FakeLauncher(output: ProcessOutput(stdout: "", stderr: "", exitCode: 1)),
            resolver: BinaryResolver(probe: FakeExecutableProbe(), environment: [:]),
            environment: [:]
        )
        let report = await HarnessInfoReport.build(from: HarnessRegistry(adapters: [ReplayAdapter(), claude]))
        let ids = report.adapters.map(\.id)
        #expect(ids.contains("replay"))
        #expect(ids.contains("claude-code"))

        let replay = report.adapters.first { $0.id == "replay" }
        #expect(replay?.available == true)
        let claudeCode = report.adapters.first { $0.id == "claude-code" }
        #expect(claudeCode?.available == false)
        #expect(claudeCode?.detail != nil)

        let json = try SkilletJSON.encode(report)
        #expect(json.contains(#""schema":"skillet.harness-info/1""#))
    }

    @Test("the default registry includes replay and claude-code")
    func defaultRegistry() {
        let ids = HarnessRegistry.default.adapters.map(\.id)
        #expect(ids.contains("replay"))
        #expect(ids.contains("claude-code"))
    }
}

/// The offline stand-in must answer as the skill it was *handed*, not as whatever happens to be sitting
/// in the staged folder — otherwise a test measuring one skill silently measures another.
@Suite("ReplayAdapter — the answer comes from the skill it was given")
struct ReplayMarkerTests {
    /// Two skills staged side by side, each carrying its own marker line.
    private func stageTwo() throws -> Workspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-marker-\(UUID().uuidString)", isDirectory: true)
        for (name, marker) in [("alpha", "first"), ("omega", "second")] {
            let dir = root.appendingPathComponent(".claude/skills/\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\nname: \(name)\n---\nreplay-marker: \(marker)\n"
                .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        return Workspace(root: root)
    }

    private func ref(_ name: String, _ workspace: Workspace) -> SkillRef {
        SkillRef(name: name, path: workspace.root.appendingPathComponent(".claude/skills/\(name)").path)
    }

    /// **Asserted through the session the grader actually reads, not the wire text.** The previous
    /// version of these tests matched the raw string, so they were coupled to a hand-made format rather
    /// than to the behaviour — and they would have gone on passing if the format had been replaced with
    /// a broken one.
    private func answer(_ workspace: Workspace, _ skills: SkillSet) async throws -> String {
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: skills)
        return try adapter.parseTrace(raw).turns.filter { $0.role == .assistant }.map(\.text)
            .joined(separator: "\n")
    }

    private func invocations(_ workspace: Workspace, _ skills: SkillSet) async throws -> Int {
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: skills)
        return try adapter.parseTrace(raw).skillInvocations.count
    }

    @Test("The skill that was loaded answers, not the first one alphabetically")
    func honorsTheRequestedSkill() async throws {
        let workspace = try stageTwo()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        #expect(try await answer(workspace, .only(load: [ref("omega", workspace)])).contains("[second]"))
        #expect(try await answer(workspace, .only(load: [ref("alpha", workspace)])).contains("[first]"))
    }

    @Test("A loaded skill is preferred over one that is merely present")
    func loadedBeatsVisible() async throws {
        let workspace = try stageTwo()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let set = SkillSet.only(load: [ref("omega", workspace)], visible: [ref("alpha", workspace)])
        #expect(try await answer(workspace, set).contains("[second]"))
    }

    @Test("A skill-free run stays skill-free, however many skills are staged")
    func baselineHasNone() async throws {
        let workspace = try stageTwo()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        #expect(try await invocations(workspace, .none) == 0, "a skill-free session fires no skill")
    }

    @Test("With no skill named, whatever is staged still answers (unchanged for existing recordings)")
    func ambientFallsBackToTheFolder() async throws {
        let workspace = try stageTwo()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        #expect(try await answer(workspace, .ambient).contains("[first]"))
    }

    @Test("An unmarked skill answers exactly as it always did")
    func unmarkedIsUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-marker-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent(".claude/skills/plain", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: plain\n---\nno marker here\n"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(root: root)
        #expect(try await answer(workspace, .only(load: [ref("plain", workspace)])) == "done",
                "no marker ⇒ the answer every existing recording has always seen")
    }
}

/// **A double needs tests of its own.** The stand-in's previous hand-made framing had none, so a marker
/// containing the character it used as a fence silently mis-graded — identical recorded grades blocked a
/// harmful edit with the marker `v1 release` and declared the same edit proven with `v[1] release`.
///
/// Driven through the real path — stage a skill, run, turn the result into a session — because that is
/// the chain that broke: reading the marker out of the file, carrying it, and putting it back in the text
/// the grader matches on. (A marker cannot contain a line break: it is read from one line of the file.)
@Suite("ReplayAdapter — the answer survives any marker text")
struct ReplayFramingTests {
    private func stage(_ marker: String) throws -> (Workspace, SkillRef) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-framing-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent(".claude/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\n---\nreplay-marker: \(marker)\n"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return (Workspace(root: root), SkillRef(name: "demo", path: dir.path))
    }

    @Test("Markers that broke the old framing now reach the grader intact",
          arguments: ["v[1] release", "]", "a]b[c", "[[[", #"quote"inside"#, "back\\slash", "後方互換"])
    func awkwardMarkersSurvive(marker: String) async throws {
        let (workspace, ref) = try stage(marker)
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: .only(load: [ref]))
        let text = try adapter.parseTrace(raw).turns
            .filter { $0.role == .assistant }.map(\.text).joined(separator: "\n")
        #expect(text.contains(marker),
                "the grader matches on this text, so a truncated marker grades against the wrong entry")
    }

    @Test("A skill-free answer stays skill-free whatever is staged")
    func baselineSurvives() async throws {
        let (workspace, _) = try stage("v[1] release")
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: .none)
        #expect(try adapter.parseTrace(raw).skillInvocations.isEmpty)
    }

    /// **The staged skill file is read through the one guarded reader.** This was the last unguarded
    /// read left in the source: it followed symbolic links and had no size limit, taking a 200 MB file
    /// in one gulp, once per attempt. The guard refuses a path that is a link, is not an ordinary file,
    /// or is over the limit — and a refusal is treated exactly as a file with no marker always was.
    /// (CERT FIO32-C: do not perform file operations on something that may not be an ordinary file.)
    @Test("A staged skill file that is a symbolic link is not followed")
    func symlinkedStagedSkillIsRefused() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-guard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent(".claude/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let elsewhere = root.appendingPathComponent("elsewhere.md")
        try "---\nname: demo\n---\nreplay-marker: leaked\n".write(to: elsewhere, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("SKILL.md"),
                                                   withDestinationURL: elsewhere)
        let workspace = Workspace(root: root)
        let ref = SkillRef(name: "demo", path: dir.path)
        let raw = try await ReplayAdapter().run(TaskSpec(query: "q"), in: workspace, skills: .only(load: [ref]))
        let text = try ReplayAdapter().parseTrace(raw).turns
            .filter { $0.role == .assistant }.map(\.text).joined()
        #expect(!text.contains("leaked"), "a link out of the staged folder must not be followed")
    }

    @Test("A staged skill file larger than the limit is refused rather than read whole")
    func oversizedStagedSkillIsRefused() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-guard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent(".claude/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let padding = String(repeating: "x", count: (1 << 20) + 1024)
        try "---\nname: demo\n---\nreplay-marker: huge\n\(padding)\n"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let workspace = Workspace(root: root)
        let ref = SkillRef(name: "demo", path: dir.path)
        let raw = try await ReplayAdapter().run(TaskSpec(query: "q"), in: workspace, skills: .only(load: [ref]))
        let text = try ReplayAdapter().parseTrace(raw).turns
            .filter { $0.role == .assistant }.map(\.text).joined()
        #expect(!text.contains("huge"), "over the limit ⇒ refused, and treated as a file with no marker")
    }

    /// **The canned answer must stay free of the characters the marker boundaries are made of.** The
    /// grader recovers a marker as the text between the first `" ["` and the final `]`. If the canned
    /// answer ever gained a `[`, or ended with `]`, those boundaries would move and the grader would look
    /// up a marker that was never there — falling back to a default and grading the wrong way, silently.
    /// Pinned here rather than left as a comment to remember.
    @Test("The canned answers cannot shift the marker boundaries",
          arguments: [ReplayAdapter.cannedTrace, ReplayAdapter.cannedBaselineTrace])
    func cannedAnswersKeepTheMarkerBoundariesIntact(trace: Trace) {
        for turn in trace.turns where turn.role == .assistant {
            #expect(!turn.text.contains("["), "a `[` here moves where the marker is read from")
            #expect(!turn.text.hasSuffix("]"), "ending in `]` moves where the marker is read to")
        }
    }

    @Test("Unreadable text falls back rather than throwing, as it always did")
    func garbageIsTolerated() throws {
        let trace = try ReplayAdapter().parseTrace(
            RawTrace(harness: HarnessID(rawValue: "replay"), raw: "not json at all"))
        #expect(!trace.turns.isEmpty)
    }
}
