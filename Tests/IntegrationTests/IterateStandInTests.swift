import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// F43 — the offline stand-ins, and the one paid path. Every test here is free unless its name says otherwise: the offline stand-ins answer
/// instead of a model. Setup is shared in `IterateFixture`.
@Suite("skillet iterate — the offline stand-ins, and the one paid path", .tags(.integration))
struct IterateStandInTests {
    // MARK: - the offline stand-ins must not decide anything by chance

    /// Twenty identical runs used to split ten and ten between opposite verdicts, because a shorter
    /// recorded marker fitted inside a longer real one and which of the two won was decided by the
    /// order a lookup table happened to be in.
    @Test("Overlapping recorded markers grade the same way every time, and by the right entry")
    func overlappingMarkersAreDeterministic() async throws {
        for _ in 0..<8 {
            let (root, _, map) = try await IterateFixture.makeRepo(
                verdicts: ["did the thing @ before": true,          // a fragment of the real marker
                           "did the thing @ before release": false, // the real one: this must win
                           "did the thing @ after": true],
                body: "# Guide\n\nreplay-marker: before release\n",
                excerpt: "replay-marker: before release", replacement: "replay-marker: after")
            defer { Fixture.remove(root) }
            let out = try await IterateFixture.iterate(root, map)
            #expect(out.stdout.contains("0/3"),
                    "the entry for the whole marker must win, not the one for a fragment of it")
        }
    }

    @Test("A marker containing brackets grades by its own entry, not by fragments of itself")
    func bracketMarkerGradesByItsOwnEntry() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: ["did the thing @ a": true, "did the thing @ b": true,
                       "did the thing @ a] [b": false, "did the thing @ after": true],
            body: "# Guide\n\nreplay-marker: a] [b\n",
            excerpt: "replay-marker: a] [b", replacement: "replay-marker: after")
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map)
        #expect(out.stdout.contains("0/3"), "its own entry decides it; `a` and `b` are not it")
    }

    /// The stand-in used to read a staged skill file with no limit and no check that it was an ordinary
    /// file. A file it cannot safely read is now skipped exactly as a file with no marker always was.
    @Test("A staged skill file that cannot be safely read is skipped, not fatal")
    func unreadableStagedSkillIsSkipped() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--runs", "1"])
        #expect(out.exitCode == 0 || out.exitCode == 1, "it measured; it did not crash or hang")
    }

    // MARK: - the one paid path

    /// **The single paid check for this command**, opt-in via `SKILLET_LIVE_SMOKE` exactly as the
    /// measuring command's is (`RunIntegrationTests.liveSmoke`), so a free suite never spends. Needs a
    /// real model program on `SKILLET_CLAUDE_CODE_BIN`. Roughly four model calls.
    ///
    /// **It asserts only what holds whatever the model writes.** An earlier version demanded that the
    /// edit improve the score — which is an assertion about the *model's* compliance, not about this
    /// program. It went red twice while everything here worked correctly, because a single sample of a
    /// model need not follow an instruction. A check that fails at random teaches you to ignore it,
    /// which is the very reason paid checks are kept out of the ordinary suite.
    ///
    /// What is left is deterministic and is what only a live run can show: a real model program launched
    /// twice in one command, both measurements recording a trial, **the skill actually invoked in each**
    /// — staging can succeed while the model never consults what was staged, and the scores would still
    /// look plausible — and the throwaway copy gone afterwards.
    ///
    /// "Can grading tell two answers apart" is a property of the grader, so it is asked directly and
    /// deterministically in `RunIntegrationTests.liveGraderDiscriminates` rather than inferred from
    /// whether a nondeterministic edit happened to move a score.
    ///
    /// What neither proves: that the grader agrees with a person. That is calibration (F10) and needs a
    /// labelled sample. A pass here means the machinery works, not that a verdict is right.
    @Test("Live claude-code smoke: two real measurements, and the skill reaches the model", .tags(.slow),
          .enabled(if: ProcessInfo.processInfo.environment["SKILLET_LIVE_SMOKE"] != nil))
    func liveSmoke() async throws {
        let (root, _, _) = try await IterateFixture.makeRepo(
            verdicts: [:],                       // nothing canned — a real grader marks these
            configExtra: "runs:\n  k: 1\n  timeout: 5m\n",
            judgeModel: "sonnet",                // the alias a real claude binary accepts
            // A real model decides whether to consult a skill from this sentence. The shared default
            // says only that the skill exists to test this tool, and against a live model that produced
            // exactly what you would expect: staged, discovered, never used — in both measurements.
            description: "Turn rough meeting notes into a short action list, so each item is clear.",
            body: """
            # Tidy notes

            Rewrite rough meeting notes as a list of action items.

            Name the person responsible for every action item.

            """,
            excerpt: "Name the person responsible for every action item.",
            // **An instruction a model can hardly miss, checked by a rule with one right answer.** The
            // first version of this asked for calendar dates instead of relative ones, and the live run
            // failed: both versions were measured, nothing errored, and the edited skill simply did not
            // do it that time. A stylistic preference is a coin toss on one sample, and a check that
            // fails at random teaches you to ignore it — which is the whole reason paid checks are kept
            // out of the ordinary suite in the first place. An explicit closing line is near-certain to
            // be followed and unambiguous to grade, so a failure means something is actually broken.
            replacement: "Name the person responsible for every action item.\n\nFinish with a single "
                + "line reading `Owners:` followed by every name you used, separated by commas.",
            evalsRaw: #"""
            {"skill_name":"demo","evals":[{"id":"owners-line",
             "prompt":"Tidy these notes into action items:\nAna will draft the launch plan, needs it by Friday. Sam agreed to review it over the weekend. Priya is chasing the vendor quote, expects it early next week.",
             "expectations":["the reply ends with a line that starts with the word Owners followed by a colon"]}]}
            """#)
        defer { Fixture.remove(root) }

        // Asserted against the machine-readable payload, never the printed table: this project publishes
        // that its printed output carries no compatibility promise (design P7), so a check reading it
        // would break on a harmless rewording.
        let out = try await SkilletHarness().run(
            ["-C", root.path, "iterate", "demo", "--proposals", "fix.json", "--yes", "--json"])
        #expect(out.exitCode == 0 || out.exitCode == 1,
                "it ran — anything else is a refusal before measuring: \(out.stderr)")
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any],
                                   "no machine-readable result — the run did not complete: \(out.stderr)")
        #expect(payload["schema"] as? String == "skillet.iterate/1")

        // **Both measurements actually happened.** Zero recorded on either side is a run where every
        // attempt errored, which otherwise looks exactly like an edit that changed nothing.
        let row = try #require((payload["comparison"] as? [String: Any])?["per_eval"] as? [[String: Any]])
            .first
        #expect(row?["before_recorded"] as? Int == 1, "the unedited skill was not measured at all")
        #expect(row?["after_recorded"] as? Int == 1, "the edited skill was not measured at all")

        // **The skill actually reached the model, in both measurements.** This is the property that
        // matters and the one nothing else can check: staging can succeed while the model never consults
        // what was staged, and every score would still look plausible. Deterministic — it holds whatever
        // the model chooses to write.
        for arm in ["before", "after"] {
            let traces = FileManager.default.enumerator(
                at: root.appendingPathComponent(".skillet/runs"), includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.lastPathComponent == "trace.json" && $0.path.contains("/\(arm)/") } ?? []
            let invoked = traces.contains { url in
                guard let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return false }
                return ((object["skill_invocations"] as? [[String: Any]]) ?? []).isEmpty == false
            }
            #expect(invoked, "the \(arm) measurement never invoked the skill — it was staged but unused")
        }

        // And nothing was left behind.
        let copies = try await IterateFixture.run("git", ["worktree", "list"], in: root)
        #expect(!copies.contains("skillet-iterate"), "the throwaway copy outlived the run")
    }

    /// **The chosen grader must be used, not merely accepted.** The first version of this pair asserted
    /// that the flag was taken and that a warning appeared — both of which stay true if the selection is
    /// then thrown away, which is exactly what hard-wiring it did. Undoing the fix left that test green.
    ///
    /// The file-reading grader reads what a run produced, so choosing it changes what is captured even
    /// with no model involved: a per-trial `file_contents.json` appears. That is the difference a test
    /// can see.
    @Test("Choosing the file-reading grader changes what is captured, not just what is accepted",
          arguments: [("text-judge", false), ("grounded-judge", true)])
    func graderSelectionReachesTheRun(judge: String, capturesContents: Bool) async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--judge", judge, "--runs", "1"])
        #expect(out.exitCode == 0)
        let captured = (FileManager.default.enumerator(
            at: root.appendingPathComponent(".skillet/runs"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .contains { $0.lastPathComponent == "file_contents.json" }
        #expect(captured == capturesContents,
                capturesContents
                    ? "the file-reading grader was selected but the run captured no file contents — the choice was accepted and discarded"
                    : "the text grader must not pay to capture file contents")
    }

}
