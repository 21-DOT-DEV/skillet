import Testing
import Foundation

/// **A run that could not grade anything must not report the skill as having got worse.**
///
/// When the program that runs the model fails — or the grader errors, or a rate limit hits — no verdict
/// is produced, so nothing is known about the skill. That used to be recorded as a measured failure and
/// the command handed back `1`, which is the number meaning "the measurement showed a real problem". A
/// pipeline reading it would block a merge over a network hiccup.
///
/// It now hands back `75`, the long-standing Unix number for a temporary failure that is worth trying
/// again. Deliberately not the environment number, which means something is set up wrong and will never
/// come right on a retry.
@Suite("A run that graded nothing reports a temporary failure, not a regression", .tags(.integration))
struct UngradedExitTests {
    /// Answers the version and sign-in probes, then fails at the actual work.
    private func makeFailingShim(dir: URL) throws -> String {
        let shim = dir.appendingPathComponent("failing-shim.sh")
        try """
        #!/bin/sh
        case "$1" in
          --version) echo "9.9.9 (Claude Code)" ;;
          auth) echo '{"loggedIn":true}' ;;
          *) echo "the model program failed" >&2; exit 1 ;;
        esac
        """.write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        return shim.path
    }

    private func makeRepo() throws -> URL {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        try "project:\n  skills_root: skills\njudge:\n  model: test-model\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("Nothing graded → exit 75 and a note, not exit 1")
    func ungradedRunIsTemporaryFailure() async throws {
        let root = try makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--runs", "1", "--yes"],
            environment: ["SKILLET_CLAUDE_CODE_BIN": try makeFailingShim(dir: root)])

        #expect(out.exitCode == 75, "nothing was graded, so nothing regressed: \(out.stdout)\(out.stderr)")
        #expect(out.exitCode != 1, "1 means the measurement showed a real problem, and it did not")
        #expect(out.stderr.contains("never graded"), "say what happened rather than leaving a bare number")
    }

    /// The reason used to be discarded entirely — caught without even being looked at.
    @Test("The reason nothing was graded is written beside the attempt")
    func reasonIsRecorded() async throws {
        let root = try makeRepo(); defer { Fixture.remove(root) }
        _ = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--runs", "1", "--yes"],
            environment: ["SKILLET_CLAUDE_CODE_BIN": try makeFailingShim(dir: root)])

        let found = FileManager.default.enumerator(atPath: root.path)?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix("metadata.json") } ?? []
        let reasons = found.compactMap { try? String(contentsOfFile: root.appendingPathComponent($0).path,
                                                     encoding: .utf8) }
            .filter { $0.contains("ungradedReason") }
        #expect(!reasons.isEmpty, "the reason must survive somewhere; found files: \(found)")
        // It has to name something actionable, not just record that something went wrong.
        #expect(reasons.contains { $0.contains("exitCode") || $0.contains("claude-code") },
                "the recorded reason must say what actually failed")
    }
}
