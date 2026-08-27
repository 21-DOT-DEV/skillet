import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// Shared setup for the suites that drive `skillet iterate` through the built binary. Split out when the
/// single file passed twice the 300-line soft cap: the tests moved into topic suites, and everything they
/// share moved here so no suite owns another's helpers.
///
/// F43 — proving a reviewed edit by measuring the skill twice. Every test is free: the offline
/// stand-ins answer instead of a model, and the skill carries a marker so the two versions can measure
/// differently without anything being paid for.
enum IterateFixture {
    /// A committed project whose skill carries `replay-marker: before`, plus a saved draft whose one
    /// edit changes that marker to `after`. Recorded verdicts key on the marker, so the two versions
    /// score differently — which is the whole point of the command.
    /// `configExtra` appends to `skillet.yaml`; `body`, `excerpt`, `replacement` and `evalsRaw` let a
    /// test vary the one thing it is about while everything else stays byte-identical to the default.
    static func makeRepo(
        verdicts: [String: Bool],
        /// The folder the skill lives in. A folder name may legally contain a space, which is what the
        /// printed-command test needs.
        skillName: String = "demo",
        configExtra: String = "",
        judgeModel: String = "claude-sonnet-4-6",
        /// **What the skill says it is for.** Irrelevant offline — the stand-in reads a marker out of the
        /// file and never decides anything — but decisive against a real model, which chooses whether to
        /// consult a skill from this sentence. The default below says only that the skill exists to test
        /// this tool, which gives a real model no reason to use it for anything; the live check therefore
        /// passes a description of an actual job.
        description: String = "A demo skill for proving edits, long enough to satisfy the lint rules.",
        body: String = "# Guide\n\nreplay-marker: before\n",
        secondEdit: (excerpt: String, replacement: String)? = nil,
        excerpt: String = "replay-marker: before",
        replacement: String = "replay-marker: after",
        evalsRaw: String? = nil
    ) async throws -> (root: URL, draft: String, map: String) {
        let root = try Fixture.makeTempDirectory()
        try await run("git", ["init", "-q"], in: root)
        try ("project:\n  skills_root: skills\njudge:\n  model: \(judgeModel)\n" + configExtra).write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)

        let skill = root.appendingPathComponent("skills/\(skillName)/evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try ("""
        ---
        name: \(skillName)
        description: \(description)
        ---

        """ + body).write(to: root.appendingPathComponent("skills/\(skillName)/SKILL.md"),
                          atomically: true, encoding: .utf8)
        try (evalsRaw ?? #"{"skill_name":"\#(skillName)","evals":[{"id":0,"prompt":"do it","expectations":["did the thing"]}]}"#).write(to: skill.appendingPathComponent("evals.json"), atomically: true, encoding: .utf8)

        let proposals = root.appendingPathComponent(".skillet/proposals", isDirectory: true)
        try FileManager.default.createDirectory(at: proposals, withIntermediateDirectories: true)
        try ".skillet is scratch\n*\n".write(to: root.appendingPathComponent(".skillet/.gitignore"),
                                             atomically: true, encoding: .utf8)
        // Assembled rather than pasted, so an excerpt spanning several lines is escaped correctly.
        let draft: [String: Any] = [
            "schema": "skillet.proposal/1", "id": "2026-08-19-demo-abcd1234", "skill": skillName,
            "motivation": [], "expected": [], "model": "m", "prompt_version": "v1",
            "request_fingerprint": "abcd1234",
            "edits": [["path": "SKILL.md", "skill_md_lines": "7", "current_excerpt": excerpt,
                       "proposed_text": replacement, "rationale": "r", "addresses": []]]
                + (secondEdit.map { [["path": "SKILL.md", "skill_md_lines": "9",
                                      "current_excerpt": $0.excerpt, "proposed_text": $0.replacement,
                                      "rationale": "r2", "addresses": []]] } ?? []),
        ]
        try JSONSerialization.data(withJSONObject: draft)
            .write(to: proposals.appendingPathComponent("fix.json"))

        // **Written before the commit, deliberately.** This command refuses a dirty repository, so a
        // fixture that drops an untracked file in afterwards makes every test fail at the gate — which is
        // exactly what happened the first time.
        let map = try Fixture.writeReplayMap(verdicts, in: root)
        try await run("git", ["add", "-A"], in: root)
        try await run("git", ["-c", "user.email=t@e", "-c", "user.name=t", "commit", "-qm", "base"], in: root)
        return (root, "fix.json", map)
    }

    /// The edit helps: failing before, passing after.
    static let improves = ["did the thing @ before": false, "did the thing @ after": true]
    /// The edit harms: the reverse.
    static let regresses = ["did the thing @ before": true, "did the thing @ after": false]

    @discardableResult
    static func run(_ tool: String, _ arguments: [String], in directory: URL) async throws -> String {
        let result = try await Subprocess.run(
            .name(tool), arguments: .init(arguments), workingDirectory: FilePath(directory.path),
            output: .string(limit: 1 << 20), error: .string(limit: 1 << 20))
        return (result.standardOutput ?? "") + (result.standardError ?? "")
    }

    /// `environment` overlays variables onto the run — used by the test that needs the version-control
    /// program to fail on one operation and behave normally otherwise.
    static func iterate(_ root: URL, _ map: String, _ extra: [String] = [],
                        environment: [String: String] = [:],
                        skillName: String = "demo") async throws -> SkilletHarness.Output {
        try await SkilletHarness().run(
            ["-C", root.path, "iterate", skillName, "--proposals", "fix.json",
             "--replay", "--replay-map", map, "--yes"] + extra,
            environment: environment)
    }

}
