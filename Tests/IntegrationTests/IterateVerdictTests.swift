import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// F43 — what the verdict says, and what it offers afterwards. Every test here is free unless its name says otherwise: the offline stand-ins answer
/// instead of a model. Setup is shared in `IterateFixture`.
@Suite("skillet iterate — what the verdict says, and what it offers afterwards", .tags(.integration))
struct IterateVerdictTests {
    // MARK: - the happy path

    @Test("A clean repository and an edit that helps: measures twice, prints both, exits 0")
    func provesAnImprovement() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("0/3") && out.stdout.contains("3/3"), "both measurements are shown")
        #expect(out.stdout.contains("no test scored lower"))
        #expect(out.stdout.contains("provisional"), "the verdict says what it is worth")
        #expect(out.stdout.contains("skillet suggest demo --proposals fix.json --apply"),
                "and hands over the command that actually lands it")
    }

    // MARK: - narrowing the draft, and what gets offered afterwards

    /// **It offers exactly what it measured.** Proving one edit and then printing the command that
    /// applies the whole draft recommends shipping edits nothing measured — the same fault as a verdict
    /// drawn from zero trials, by a different route.
    @Test("Proving a subset offers a land command limited to that subset")
    func landCommandNamesOnlyWhatWasProven() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves,
            body: "# Guide\n\nreplay-marker: before\n\nsecond passage here\n",
            secondEdit: ("second passage here", "second passage changed"))
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--edits", "0"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("--apply --edits 0"),
                "the offer must not reach edit 1, which was never measured")
    }

    @Test("Proving the whole draft offers the plain land command, with no redundant flag")
    func landCommandOmitsTheFlagWhenNothingWasNarrowed() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves,
            body: "# Guide\n\nreplay-marker: before\n\nsecond passage here\n",
            secondEdit: ("second passage here", "second passage changed"))
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--edits", "0", "1"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("--proposals fix.json --apply\n") ||
                out.stdout.hasSuffix("--proposals fix.json --apply\n"),
                "everything proven ⇒ the short command it has always been")
    }

    @Test("Naming the same edit twice is a mistyped command, not a safety refusal")
    func duplicateEditsAreMisuse() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--edits", "0", "0"])
        #expect(out.exitCode == 2, "mistyped, so 2 — not 5, which means a deliberate check said no")
        #expect(out.stderr.contains("names edit 0 more than once"))
        #expect(!out.stderr.contains("overlapping"), "an edit cannot overlap itself")
        #expect(!out.stderr.contains("one at a time with --edits"),
                "and must not advise the very flag that carried the mistake")
    }

    @Test("The preview counts read grammatically at one, in the same command as the verdict line")
    func previewCountsReadGrammatically() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--dry-run"])
        #expect(out.stdout.contains("1 eval ×"), "one eval is one eval")
        #expect(!out.stdout.contains("(s)"),
                "fixing the verdict line and leaving this one makes the same command inconsistent with itself")
    }

    @Test("A regression of exactly one test reads as one test")
    func singleRegressionReadsGrammatically() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.regresses); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 1)
        #expect(out.stdout.contains("1 test scored lower"))
        #expect(!out.stdout.contains("test(s)"))
    }

    /// **A preview asked for machine-readable output must give one.** Every command here offers one and
    /// every payload carries a schema; this branch used to hand back prose regardless, so a script asking
    /// for a plan got a table meant for a person and had to read it by eye.
    @Test("--dry-run --json emits a schema-bearing plan, not prose")
    func previewAnswersAMachine() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves)
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--dry-run", "--json", "--runs", "2"])
        #expect(out.exitCode == 0)
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any],
                                   "the preview did not answer in machine-readable form: \(out.stdout)")
        #expect(payload["schema"] as? String == "skillet.iterate-plan/1")
        #expect(payload["skill"] as? String == "demo")
        #expect(payload["k"] as? Int == 2)
        // One test, two repeats, two measurements — and one answer plus one grading per trial.
        #expect(payload["trials"] as? Int == 4)
        #expect(payload["estimated_calls"] as? Int == 8)
        #expect(payload["requires_confirmation"] as? Bool == false)
        #expect(payload["will_spend"] as? Bool == false, "the offline stand-ins spend nothing")
    }

    @Test("Without --json the preview still reads as prose")
    func previewStillReadsForPeople() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves)
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--dry-run"])
        #expect(out.stdout.contains("nothing measured, nothing spent"))
        #expect(!out.stdout.contains("\"schema\""))
    }

    // MARK: - the promises

    @Test("Nothing is committed, nothing is staged, and the skill file is untouched")
    func changesNothingYouOwn() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let file = root.appendingPathComponent("skills/demo/SKILL.md")
        let before = try String(contentsOf: file, encoding: .utf8)
        let head = try await IterateFixture.run("git", ["rev-parse", "HEAD"], in: root)

        _ = try await IterateFixture.iterate(root, map)
        #expect(try await IterateFixture.run("git", ["rev-parse", "HEAD"], in: root) == head, "nothing was committed")
        let staged = try await IterateFixture.run("git", ["diff", "--cached", "--name-only"], in: root)
        #expect(staged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "nothing was staged")
        #expect(try String(contentsOf: file, encoding: .utf8) == before, "your skill is byte-identical")
    }

    @Test("--dry-run reports the doubled cost and spends nothing")
    func previewSpendsNothing() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--dry-run"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("2 measurements"), "the doubling is stated, not left to be inferred")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".skillet/runs").path))
    }

    @Test("Declining the cost leaves 5, and names the way out")
    func declinedCostRefuses() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        try "project:\n  skills_root: skills\nruns:\n  confirm_above_trials: 1\njudge:\n  model: claude-sonnet-4-6\n"
            .write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        try await IterateFixture.run("git", ["add", "-A"], in: root)
        try await IterateFixture.run("git", ["-c", "user.email=t@e", "-c", "user.name=t", "commit", "-qm", "gate"], in: root)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "iterate", "demo", "--proposals", "fix.json",
             "--replay", "--replay-map", map, "--no-input"])
        #expect(out.exitCode == 5, "a deliberate check said no — see Specs/020 D8")
        #expect(out.stderr.contains("--yes"), "and says how to proceed")
    }

    @Test("--json emits skillet.iterate/1 with the paired block, agreeing with what was printed")
    func machineReadable() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--json"])
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any])
        #expect(json["schema"] as? String == "skillet.iterate/1")
        #expect(json["proven"] as? Bool == true)
        #expect(json["provisional"] as? Bool == true, "the caveat travels with the machine-readable form too")
        let comparison = try #require(json["comparison"] as? [String: Any])
        let rows = try #require(comparison["per_eval"] as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["delta"] as? Double == 1.0, "0/3 → 3/3 is a whole-unit improvement")
    }

    /// **A script is told what a person is shown.** The printed result ends with the command that applies
    /// the edit for real; the machine-readable result used to omit it, so anything automating this had to
    /// rebuild that command from its parts — and getting one switch wrong there means applying edits
    /// nothing measured. It is present only next to a positive verdict, for the same reason it is not
    /// printed next to a negative one: there is nothing to apply.
    @Test("--json carries the command that applies the edit, and only when the edit held up")
    func machineReadableCarriesLandCommand() async throws {
        let (root, draft, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--json"])
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any])
        let land = try #require(json["land_command"] as? String, "the applying command has to be in the payload")
        #expect(land.contains("suggest"), "and it must be the command that applies a reviewed draft")
        #expect(land.contains("--apply"))
        #expect(land.contains(draft), "naming the very draft that was measured")

        let (bad, _, badMap) = try await IterateFixture.makeRepo(verdicts: IterateFixture.regresses); defer { Fixture.remove(bad) }
        let refused = try await IterateFixture.iterate(bad, badMap, ["--json"])
        let refusedJSON = try #require(try JSONSerialization.jsonObject(with: Data(refused.stdout.utf8)) as? [String: Any])
        #expect(refusedJSON["proven"] as? Bool == false)
        #expect(refusedJSON["land_command"] == nil,
                "an edit that scored worse must not come with the command that ships it")
    }
}
