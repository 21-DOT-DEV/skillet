import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// Shared setup for the suites that put one scenario to every command that spends. Split out when the
/// single file passed the 300-line soft cap; the reasoning for testing them together is below and has
/// not changed.
///
/// **The same settings, put to every command that spends, requiring the same answer.**
///
/// One defect appeared five times over this feature: a refusal present in `run` and simply absent from
/// `iterate` — the sign-in check, the cost question, three free refusals, the scratch-folder guard, the
/// repetition guard, the output-cap guard. Each was found by a person reading code, and fixing each one
/// did nothing about the next.
///
/// Testing each command separately cannot catch this class, because the bug is never in what a command
/// does — it is in what a command *omits*, and an omission has no line to put a test on. Running one
/// scenario against every command and requiring identical answers puts the omission itself under test.
///
/// **This is one of two halves.** It cannot see a *new* paid command, because the list below is written
/// by hand — that half is covered by the compiler: the routine that picks the model and grader will not
/// accept anything except the value the settings gate returns (`SpendGate.Approved`), so a command that
/// skips the gate does not build. This half covers what that cannot: two commands that both call the
/// gate but disagree about what they feed it.
enum PaidCommandFixture {
    /// Every command that can spend, with the arguments that get it as far as reading settings.
    /// A new paid command is added here; forgetting is caught by the compiler, not by this list.
    static let paid: [(name: String, arguments: [String])] = [
        ("run", ["run", "demo", "--replay"]),
        ("iterate", ["iterate", "demo", "--proposals", "fix.json", "--replay", "--yes"]),
    ]

    /// The commands that narrow a draft with `--edits`. `run` has no draft, so it is not one of them.
    static let narrowing: [(name: String, arguments: [String])] = [
        ("suggest --apply", ["suggest", "demo", "--proposals", "fix.json", "--apply"]),
        ("iterate", ["iterate", "demo", "--proposals", "fix.json", "--replay", "--yes"]),
    ]

    static func selections(_ extra: [String]) async throws -> [(String, SkilletHarness.Output)] {
        var collected: [(String, SkilletHarness.Output)] = []
        for command in narrowing {
            let root = try await makeRepo(runs: "")
            defer { Fixture.remove(root) }
            collected.append((command.name,
                              try await SkilletHarness().run(["-C", root.path] + command.arguments + extra)))
        }
        return collected
    }

    /// A committed project whose settings block is written per-test.
    static func makeRepo(runs: String, evalsRaw: String? = nil) async throws -> URL {
        let root = try Fixture.makeTempDirectory()
        try await git(["init", "-q"], in: root)
        try ("project:\n  skills_root: skills\njudge:\n  model: claude-sonnet-4-6\n" + runs)
            .write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let evaluations = root.appendingPathComponent("skills/demo/evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: evaluations, withIntermediateDirectories: true)
        try """
        ---
        name: demo
        description: A demo skill for the shared-settings parity checks, long enough to satisfy lint.
        ---
        # Guide

        replay-marker: before

        second passage here

        """.write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        try (evalsRaw ?? #"{"skill_name":"demo","evals":[{"id":"e1","prompt":"do","expectations":["did the thing"]}]}"#)
            .write(to: evaluations.appendingPathComponent("evals.json"), atomically: true, encoding: .utf8)

        let proposals = root.appendingPathComponent(".skillet/proposals", isDirectory: true)
        try FileManager.default.createDirectory(at: proposals, withIntermediateDirectories: true)
        try ".skillet is scratch\n*\n".write(to: root.appendingPathComponent(".skillet/.gitignore"),
                                             atomically: true, encoding: .utf8)
        let draft: [String: Any] = [
            "schema": "skillet.proposal/1", "id": "2026-08-19-demo-abcd1234", "skill": "demo",
            "motivation": [], "expected": [], "model": "m", "prompt_version": "v1",
            "request_fingerprint": "abcd1234",
            "edits": [["path": "SKILL.md", "skill_md_lines": "7",
                       "current_excerpt": "replay-marker: before",
                       "proposed_text": "replay-marker: after", "rationale": "r", "addresses": []],
                      ["path": "SKILL.md", "skill_md_lines": "9",
                       "current_excerpt": "second passage here",
                       "proposed_text": "second passage changed", "rationale": "r2", "addresses": []]],
        ]
        try JSONSerialization.data(withJSONObject: draft)
            .write(to: proposals.appendingPathComponent("fix.json"))
        // Before the commit: this feature refuses a repository with uncommitted work.
        try await git(["add", "-A"], in: root)
        try await git(["-c", "user.email=t@e", "-c", "user.name=t", "commit", "-qm", "base"], in: root)
        return root
    }

    @discardableResult
    static func git(_ arguments: [String], in directory: URL) async throws -> String {
        let result = try await Subprocess.run(
            .name("git"), arguments: .init(arguments), workingDirectory: FilePath(directory.path),
            output: .string(limit: 1 << 20), error: .string(limit: 1 << 20))
        return (result.standardOutput ?? "") + (result.standardError ?? "")
    }

    /// Put one settings file to every paid command and collect what each did.
    ///
    /// **A fresh repository per command, deliberately.** Sharing one lets the first command's side
    /// effects change what the second sees — a successful measurement writes a record inside the skill,
    /// which leaves uncommitted work, which the proving command refuses on sight. That would have been a
    /// property of the test order rather than of the commands.
    static func answers(runs: String, extra: [String] = [],
                        evalsRaw: String? = nil) async throws -> [(String, SkilletHarness.Output)] {
        var collected: [(String, SkilletHarness.Output)] = []
        for command in paid {
            let root = try await makeRepo(runs: runs, evalsRaw: evalsRaw)
            defer { Fixture.remove(root) }
            collected.append((command.name,
                              try await SkilletHarness().run(["-C", root.path] + command.arguments + extra)))
        }
        return collected
    }

}
