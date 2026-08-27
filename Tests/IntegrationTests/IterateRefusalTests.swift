import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// F43 — what it refuses, and when. Every test here is free unless its name says otherwise: the offline stand-ins answer
/// instead of a model. Setup is shared in `IterateFixture`.
@Suite("skillet iterate — what it refuses, and when", .tags(.integration))
struct IterateRefusalTests {
    // MARK: - the refusals

    @Test("An edit that makes a test worse ⇒ exit 1, and the verdict says so")
    func regressionBlocks() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.regresses); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 1, "measured and negative — not a malfunction")
        #expect(out.stdout.contains("scored lower"))
        #expect(!out.stdout.contains("skillet suggest"), "never offer to land an edit that failed")
    }

    @Test("Uncommitted work anywhere ⇒ refused before spending, and no copy is made")
    func dirtyRepositoryRefuses() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        try "scratch\n".write(to: root.appendingPathComponent("unrelated.txt"), atomically: true, encoding: .utf8)
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 5)
        #expect(out.stderr.contains("uncommitted changes"))
        #expect(out.stderr.contains("more than the edit"), "say why a clean tree is required, not just that it is")
        let copies = try await IterateFixture.run("git", ["worktree", "list"], in: root)
        #expect(copies.components(separatedBy: "\n").filter { !$0.isEmpty }.count == 1, "no copy was made")
    }

    @Test("A quoted passage that has moved ⇒ refused, nothing measured, copy removed")
    func driftRefuses() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        // Change the passage the draft quotes, then commit so the tree is clean again.
        let file = root.appendingPathComponent("skills/demo/SKILL.md")
        try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "replay-marker: before", with: "replay-marker: elsewhere")
            .write(to: file, atomically: true, encoding: .utf8)
        try await IterateFixture.run("git", ["add", "-A"], in: root)
        try await IterateFixture.run("git", ["-c", "user.email=t@e", "-c", "user.name=t", "commit", "-qm", "moved"], in: root)

        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 5)
        #expect(out.stderr.contains("no longer in the file"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".skillet/runs").path),
                "refused before measuring, so nothing was spent")
        let copies = try await IterateFixture.run("git", ["worktree", "list"], in: root)
        #expect(copies.components(separatedBy: "\n").filter { !$0.isEmpty }.count == 1, "the copy was removed")
    }

    // MARK: - everything free, before anything paid

    @Test("A test naming a fixture that isn't there is refused before spending, not skipped silently")
    func missingFixtureRefuses() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves,
            evalsRaw: #"{"skill_name":"demo","evals":[{"id":0,"prompt":"do it","expectations":["did the thing"],"files":["fixtures/nope.txt"]}]}"#
        )
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 4, "the same class the measuring command gives for the same fault")
        #expect(out.stderr.contains("fixture that is missing"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".skillet/runs").path),
                "refused before anything was measured")
    }

    @Test("An edit that leaves the skill invalid is refused for free, before the cost question")
    func breakingEditRefusedFree() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves,
            configExtra: "lint:\n  body_error_lines: 6\n",
            replacement: "replay-marker: after\nx\nx\nx\nx\nx\nx"   // 9-line body in the copy
        )
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 2, "a pre-measurement refusal, not a measured failure")
        #expect(out.stdout.contains("SKILL-L003"), "and it names the rule the edited version breaks")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".skillet/runs").path),
                "nothing was spent proving an edit that breaks the file")
    }

    /// **The half that decides where the static check points.** Aiming it at the skill as it stands would
    /// refuse the repair itself — the most valuable edit this command can prove. Aimed at the edited copy,
    /// the repair goes through and a *breaking* edit is still caught (above).
    @Test("An edit that repairs an already-invalid skill is measured, not blocked")
    func repairingEditIsNotBlocked() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves,
            configExtra: "lint:\n  body_error_lines: 4\n",
            body: "# Guide\n\nreplay-marker: before\nfiller\nfiller\nfiller\n",   // 6 lines: invalid
            excerpt: "replay-marker: before\nfiller\nfiller\nfiller",
            replacement: "replay-marker: after"                                     // 3 lines: valid
        )
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 0, "the repair was proven, not refused for the fault it repairs")
        #expect(out.stdout.contains("no test scored lower"))
    }

    @Test("--dry-run reports a broken edit rather than promising a measurement that would refuse")
    func previewCatchesABrokenEdit() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves,
            configExtra: "lint:\n  body_error_lines: 6\n",
            replacement: "replay-marker: after\nx\nx\nx\nx\nx\nx"
        )
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--dry-run"])
        #expect(out.exitCode == 2)
        #expect(!out.stdout.contains("2 measurements"), "no cost estimate for a plan that cannot run")
    }

    // MARK: - measuring nothing is never a pass

    /// **The worst shape this command can take.** With no repetitions there are no trials, every test
    /// reports 0/0, nothing "scored lower", and the command declared the edit proven, exited 0, and
    /// printed the command to land it — a recommendation to ship an edit that was never measured.
    @Test("Zero repetitions refuses instead of proving an edit nothing measured")
    func zeroRepetitionsNeverProves() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--runs", "0"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("--runs must be at least 1"), "and names the flag that supplied it")
        #expect(!out.stdout.contains("0/0"), "no comparison is drawn from nothing")
        #expect(!out.stdout.contains("skillet suggest"), "and nothing is recommended for landing")
    }

    @Test("A repetition count of zero in the settings file blames the setting, not a flag nobody typed")
    func zeroRepetitionsFromSettingsBlamesTheSetting() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves, configExtra: "runs:\n  k: 0\n")
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("runs.k must be at least 1"))
        #expect(!out.stderr.contains("--runs must be"), "nobody typed a flag here")
    }

    /// The declared default is 64 MiB; this command had 4 MiB typed by hand, small enough to cut off a
    /// long session and record the attempt as a failure that has nothing to do with the skill.
    @Test("The output cap comes from the one place that declares it, and a bad one is refused")
    func outputCapIsShared() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves, configExtra: "runs:\n  max_output_bytes: 0\n")
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("runs.max_output_bytes must be positive"))
    }

    @Test("A time limit the tool cannot read is refused, not silently turned into ten minutes")
    func unreadableTimeLimitRefuses() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves, configExtra: "runs:\n  timeout: \"10 minutes\"\n")
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("runs.timeout is not a duration"))
        #expect(out.stderr.contains("10m"), "and shows a form that works")
    }

}
