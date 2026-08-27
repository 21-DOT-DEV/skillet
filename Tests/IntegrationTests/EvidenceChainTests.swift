import Testing
import Foundation

/// **The evidence loop is run as one chain here, instead of each link against a fixture someone typed.**
///
/// The loop is: cluster the problems found in recorded sessions into finding files, then draft an edit
/// from one of those findings. Both halves were well covered — and separately. The drafting half was only
/// ever given finding files written by hand in the test itself, so nothing checked that a file the
/// clustering step *actually produces* can be used by the drafting step: not its name, not what is inside
/// it, not the identifier used to ask for it. A hand-written fixture can drift from the real thing without
/// a single test noticing, and the seam between two commands is exactly where that costs you.
///
/// This mirrors the same gap found and closed for the proving step, which printed the command that lands
/// an edit while no test ever ran it.
///
/// Nothing here is paid: the drafting step is given a canned reply through its offline switch. The command
/// is otherwise exactly the one the clustering step printed.
@Suite("Clustered findings can actually be drafted from", .tags(.integration))
struct EvidenceChainTests {
    /// A project with recorded sessions that all hit the same known problem, which is what gives the
    /// clustering step something to cluster.
    private func repoWithFindings(_ toolVersion: String) throws -> URL {
        let root = try Fixture.makeTempDirectory()
        try "project:\n  skills_root: skills\nsuggest:\n  model: claude-sonnet-4-6\n"
            .write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let skill = root.appendingPathComponent("skills/demo", isDirectory: true)
        let sessions = skill.appendingPathComponent("evaluations/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a fixture for the evidence chain, long enough for the rules\n---\nBody.\n"
            .write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        for stem in ["a", "b", "c"] {
            try #"{"id":"\#(stem)","skill":"demo","skill_version":"1.0.0","model":"opus","harness":"claude-code","captured_at":"2026-06-01T00:00:00Z","schema_version":2}"#
                .write(to: sessions.appendingPathComponent("\(stem).session-meta.json"), atomically: true, encoding: .utf8)
            try #"{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"skillet","version":"\#(toolVersion)"}},"results":[{"ruleId":"SKILL-S001","level":"warning","message":{"text":"filler phrase"}}]}]}"#
                .write(to: sessions.appendingPathComponent("\(stem).audit-input.sarif"), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test("A finding the clustering step wrote can be drafted from, using the command it printed")
    func clusteredFindingCanBeDraftedFrom() async throws {
        let version = try await TriageIntegrationTests.currentVersion()
        let root = try repoWithFindings(version); defer { Fixture.remove(root) }

        let clustered = try await SkilletHarness().run(["-C", root.path, "triage", "demo"])
        #expect(clustered.exitCode == 0, "\(clustered.stderr)")

        // The command it tells you to run next, taken from what it printed rather than rebuilt here.
        let printed = clustered.stdout.components(separatedBy: " · ")
            .first { $0.contains("skillet suggest") }
        let line = try #require(printed, "clustering must offer a way to draft from what it found: \(clustered.stdout)")
        var parts = line.components(separatedBy: "skillet suggest").last!
            .split(whereSeparator: \.isWhitespace).map(String.init)
        #expect(parts.contains("--from"), "and it names the finding to draft from: \(line)")

        // A canned reply, so the drafting step calls no model and nothing is spent. It must live inside
        // the project — a reply from outside is refused, which is itself worth knowing here.
        let reply = root.appendingPathComponent("reply.json")
        try #"{"edits":[{"path":"SKILL.md","current_excerpt":"Body.","proposed_text":"Body, revised.","rationale":"r","addresses":[]}],"motivation":[],"expected":[]}"#
            .write(to: reply, atomically: true, encoding: .utf8)
        // **Named relative to the project, not to wherever the test happens to be running.** That is the
        // convention every other file this command takes uses, and it used to mean "relative to the
        // folder you are standing in" — so running from anywhere else looked in the wrong place and then
        // refused what it found, or found nothing. Passing the full path here would have exercised none
        // of that.
        parts += ["--out", "draft.json", "--reply-file", "reply.json"]

        let drafted = try await SkilletHarness().run(["-C", root.path, "suggest"] + parts)
        #expect(drafted.exitCode == 0,
                "a finding this tool wrote must be usable by the command it recommended: \(drafted.stderr)")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".skillet/proposals/draft.json").path),
                "and the draft it promised must exist")
    }

    /// The identifier the clustering step prints must be the one the drafting step accepts — a name that
    /// looks right but is not found is the failure this chain exists to catch.
    @Test("An identifier the clustering step did not write is refused")
    func unknownIdentifierRefused() async throws {
        let version = try await TriageIntegrationTests.currentVersion()
        let root = try repoWithFindings(version); defer { Fixture.remove(root) }
        _ = try await SkilletHarness().run(["-C", root.path, "triage", "demo"])
        let reply = root.appendingPathComponent("reply.json")
        try #"{"edits":[],"motivation":[],"expected":[]}"#.write(to: reply, atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-01-01-not-a-real-finding",
             "--out", "draft.json", "--reply-file", reply.path])
        #expect(out.exitCode != 0, "a name that was never written must not draft from nothing")
    }
}
