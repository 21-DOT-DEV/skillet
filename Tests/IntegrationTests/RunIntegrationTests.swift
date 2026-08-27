import Testing
import Foundation

/// Drives `skillet run` through the built binary over the hidden replay path (no live harness/model),
/// proving the exit-code contract, the spend gate, and that committed records are written. The one
/// paid path is the opt-in env-gated live smoke at the bottom (skipped in free CI).
@Suite("skillet run via the binary", .tags(.integration))
struct RunIntegrationTests {
    private func benchmarkPath(_ root: URL, skill: String = "demo") -> String {
        root.appendingPathComponent("skills/\(skill)/evaluations/benchmark.json").path
    }

    @Test("All-pass replay → pass^k table, exit 0, benchmark.json + grading.json written")
    func allPass() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("pass^k"))
        #expect(FileManager.default.fileExists(atPath: benchmarkPath(root)))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("skills/demo/evaluations/grading.json").path))
    }

    @Test("--json emits the skillet.run/1 payload")
    func jsonSchema() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--json"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains(#""schema":"skillet.run/1""#))
    }

    @Test("A failed expectation → measured failure (exit 1)")
    func measuredFailure() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["X"])]); defer { Fixture.remove(root) }
        let map = try Fixture.writeReplayMap(["X": false], in: root)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--replay-map", map])
        #expect(out.exitCode == 1)
    }

    @Test("-n/--dry-run previews the plan and spends nothing (exit 0, no records)")
    func dryRun() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "-n"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("nothing spent"))
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))   // nothing written
    }

    @Test("--json --dry-run emits the skillet.run-plan/1 payload, exit 0, no records")
    func dryRunJSON() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["X"]), ("e2", ["Y"])]); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--dry-run", "--json"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains(#""schema":"skillet.run-plan/1""#))
        #expect(out.stdout.contains(#""evals":2"#))
        #expect(out.stdout.contains(#""will_spend":false"#))   // --replay never spends
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    @Test("A present-but-undecodable repo skillet.yaml fails loud (exit 4), not silent defaults")
    func invalidRepoConfigRejected() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        try "project:\n\tskills_root: skills\n".write(   // tab indentation → invalid YAML
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--dry-run"])
        #expect(out.exitCode == 4)
    }

    @Test("An explicit --config that doesn't exist is a usage error (exit 2)")
    func explicitConfigMissing() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let missing = root.appendingPathComponent("nope.yaml").path
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--config", missing, "--replay", "--dry-run"])
        #expect(out.exitCode == 2)
    }

    @Test("A symlinked evaluations/ is rejected before any read or write (exit 4, no escape)")
    func symlinkedEvaluationsRejected() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let outside = try Fixture.makeTempDirectory(); defer { Fixture.remove(outside) }
        try #"{"skill_name":"demo","evals":[{"id":"e1","prompt":"p","expectations":["x"]}]}"#
            .write(to: outside.appendingPathComponent("evals.json"), atomically: true, encoding: .utf8)
        let evaluations = root.appendingPathComponent("skills/demo/evaluations")
        try FileManager.default.removeItem(at: evaluations)
        try FileManager.default.createSymbolicLink(at: evaluations, withDestinationURL: outside)

        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4)
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("benchmark.json").path))   // never wrote through the link
    }

    @Test("Over confirm_above_trials with --no-input → exit 2 carrying the estimate")
    func spendGate() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--runs", "30", "--no-input"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("confirm_above_trials"))
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))   // refused before spending
    }

    /// **Which refusal answers first, pinned before the confirmation routine moves.**
    ///
    /// Two things are wrong at once here: the run costs more than the configured threshold, and the
    /// model program cannot be started. The cost refusal must answer, not the program one — that is the
    /// order both paid commands use today, and a later change that shares this routine between commands
    /// could reorder the two checks while still leaving the same number behind. Pinning only the number
    /// would let that through, and a person would start seeing a different error for the same mistake.
    @Test("With both an over-threshold cost and an unusable model program, the cost refuses first")
    func spendGateAnswersBeforeReadiness() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let broken = root.appendingPathComponent("not-a-program")
        try "this is not a program".write(to: broken, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: broken.path)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--runs", "30", "--no-input"],
            environment: ["SKILLET_CLAUDE_CODE_BIN": broken.path])
        #expect(out.exitCode == 2, "the cost is what refused — not the unusable program, which would be 3")
        #expect(out.stderr.contains("confirm_above_trials"), "and it says so")
        #expect(!out.stderr.contains("could not be used"), "the program refusal must not be the one shown")
    }

    @Test("Unknown skill → usage error (exit 2)")
    func unknownSkill() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "nope", "--replay"])
        #expect(out.exitCode == 2)
    }

    @Test("Corrupt evals.json → artifact error (exit 4)")
    func corruptEvals() async throws {
        let root = try Fixture.makeRunRepo(evalsRaw: "not json{"); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4)
    }

    @Test("A pinned-but-unreachable harness fails probe before any spend (exit 3)")
    func harnessProbeFails() async throws {
        let root = try Fixture.makeRunRepo(harnessPath: "/no/such/claude-binary"); defer { Fixture.remove(root) }
        // No --replay → the real claude-code adapter; the pinned bogus path fails probe up front.
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--yes"])
        #expect(out.exitCode == 3)
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))   // never ran a trial
    }

    @Test("The committed benchmark.json carries the offline pass^k basis in consistency (P2/D3)")
    func committedRecordCarriesCounts() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["X"]), ("e2", ["Y"])]); defer { Fixture.remove(root) }
        let map = try Fixture.writeReplayMap(["X": true, "Y": false], in: root)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--replay-map", map, "--runs", "1"])
        #expect(out.exitCode == 1)   // e2 fails
        // Delete the cache; the committed record must still hold the per-eval pass^k basis (constitution P2/D3).
        try? FileManager.default.removeItem(at: root.appendingPathComponent(".skillet"))
        let data = try Data(contentsOf: URL(fileURLWithPath: benchmarkPath(root)))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // runs[] is per-trial (2 evals × k=1) and viewer-shaped (string arm label).
        let runs = try #require(json["runs"] as? [[String: Any]])
        #expect(runs.count == 2)
        #expect((runs[0]["configuration"] as? String) == "default")
        // pass^k basis lives in consistency.per_eval (perfect_passes/runs), NOT the viewer's per-run result.
        let consistency = try #require(json["consistency"] as? [String: Any])
        #expect((consistency["suite_pass_power_k"] as? Double) == 0.5)   // 1 of 2 evals pass^k
        let perEval = try #require(consistency["per_eval"] as? [[String: Any]])
        #expect(perEval.contains { ($0["eval_id"] as? String) == "e1" && ($0["perfect_passes"] as? Double) == 1 })
        #expect(perEval.contains { ($0["eval_id"] as? String) == "e2" && ($0["perfect_passes"] as? Double) == 0 })
        // The ACTUAL judge backend is stamped (replay here), not the configured claude-code default.
        let metadata = try #require(json["metadata"] as? [String: Any])
        #expect(((metadata["judge"] as? [String: Any])?["provider"] as? String) == "replay")
        // M3 provenance in the COMMITTED record: judge prompt version + executor binary version
        // (probe-reported — "replay-1" on the replay seam) survive the cache wipe above.
        #expect(((metadata["judge"] as? [String: Any])?["prompt_version"] as? String) == "replay")
        #expect((metadata["executor_binary_version"] as? String) == "replay-1")
    }

    @Test("run refuses without an explicit judge.model (exit 2) — required-explicit, design §14-4")
    func missingJudgeModelRefused() async throws {
        // No judge.model in the config. The pinned-but-bogus binary proves the refusal fires BEFORE
        // binary resolution/probe (otherwise this would be the probe's exit 3); nothing is spent.
        let root = try Fixture.makeRunRepo(harnessPath: "/no/such/claude", judgeModel: nil); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("judge.model"))
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))   // no records written
    }

    @Test("run writes .skillet/.gitignore so the cache stays ignored even without a prior init")
    func cacheGitignored() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 0)
        let ignore = root.appendingPathComponent(".skillet/.gitignore")
        #expect(FileManager.default.fileExists(atPath: ignore.path))
        let cacheIgnore = try? String(contentsOf: root.appendingPathComponent(".skillet/.gitignore"), encoding: .utf8)
        // Self-ignoring on purpose, and self-documenting (the convention generated cache folders use).
        #expect(cacheIgnore?.contains("*") == true)
        #expect(cacheIgnore?.contains("Created by skillet automatically") == true)
    }

    @Test("Two runs in quick succession use distinct cache dirs (no same-second collision)")
    func distinctCacheDirs() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        _ = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        _ = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        let runsDir = root.appendingPathComponent(".skillet/runs")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: runsDir.path)) ?? []
        #expect(entries.count == 2)   // two distinct <ts>-<uuid> dirs, neither overwrote the other
    }

    @Test("A symlinked .skillet cache is rejected before any write (exit 4, no escape)")
    func symlinkedCacheRejected() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let outside = try Fixture.makeTempDirectory(); defer { Fixture.remove(outside) }
        // Redirect the entire cache outside the repo via a symlinked `.skillet`.
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".skillet"), withDestinationURL: outside)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4)
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent(".gitignore").path))   // never wrote through the link
    }

    @Test("A symlinked SKILL.md is rejected before it is read (exit 4)")
    func symlinkedSkillMdRejected() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let outside = try Fixture.makeTempDirectory(); defer { Fixture.remove(outside) }
        let realMd = outside.appendingPathComponent("SKILL.md")
        try "---\nname: demo\ndescription: ok\n---\nBody.\n".write(to: realMd, atomically: true, encoding: .utf8)
        let skillMd = root.appendingPathComponent("skills/demo/SKILL.md")
        try FileManager.default.removeItem(at: skillMd)
        try FileManager.default.createSymbolicLink(at: skillMd, withDestinationURL: realMd)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4)   // assertNoSymlinkEscape rejects it before any read/spend
    }

    // MARK: - free lint gate (free-before-paid)

    @Test("A lint-invalid skill is refused before probe/spend (exit 2, skillet.lint/1, no records/cache)")
    func lintGateRefusesBeforeProbe() async throws {
        let root = try Fixture.makeRunRepo(harnessPath: "/no/such/claude"); defer { Fixture.remove(root) }
        // Over-long description → SKILL-L001 error; evals stay valid, so this is a lint refusal (2), not exit 4.
        let longDescription = String(repeating: "x", count: 1100)
        try "---\nname: demo\ndescription: \(longDescription)\n---\nBody.\n"
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        // NON-replay: were lint not preempting, the bogus harness path would fail probe with exit 3.
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--json"])
        #expect(out.exitCode == 2)                                    // lint refusal preempts the exit-3 probe
        #expect(out.stdout.contains(#""schema":"skillet.lint/1""#))   // reason stays machine-readable
        #expect(out.stdout.contains("SKILL-L001"))
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))                            // no records
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".skillet").path))   // no cache
    }

    @Test("lint.disable suppresses the error so run proceeds to the normal path")
    func lintDisableLetsRunProceed() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let longDescription = String(repeating: "x", count: 1100)
        try "---\nname: demo\ndescription: \(longDescription)\n---\nBody.\n"
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        // Disable L001 so the over-long description no longer blocks the run.
        try "project:\n  skills_root: skills\nlint:\n  disable: [SKILL-L001]\n"
            .write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 0)   // lint suppressed → normal replay all-pass
    }

    @Test("An unsupported judge.provider is rejected before spend (exit 2)")
    func unsupportedProvider() async throws {
        let root = try Fixture.makeRunRepo(judgeProvider: "anthropic-api"); defer { Fixture.remove(root) }
        // No --replay → the real judge path, which validates the provider before resolving/spending.
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--yes"])
        #expect(out.exitCode == 2)
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    @Test("A declared but missing fixture fails loud before spend (exit 4)")
    func missingFixture() async throws {
        let root = try Fixture.makeRunRepo(
            evalsRaw: #"{"skill_name":"demo","evals":[{"id":"e1","prompt":"do","expectations":["x"],"files":["fixtures/missing.csv"]}]}"#
        )
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4)
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    @Test("--runs below 1 is a usage error (exit 2), nothing written")
    func runsBelowOneRejected() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--runs", "0"])
        #expect(out.exitCode == 2)
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    @Test("An absolute / out-of-skill fixture is rejected before spend (exit 4), never exposed")
    func outOfSkillFixtureRejected() async throws {
        // /etc/hosts exists, so this proves *absolute* paths are rejected on policy, not just missing ones.
        let root = try Fixture.makeRunRepo(
            evalsRaw: #"{"skill_name":"demo","evals":[{"id":"e1","prompt":"do","expectations":["x"],"files":["/etc/hosts"]}]}"#
        )
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4)
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    @Test("An eval with no expectations is rejected before spend (exit 4)")
    func zeroExpectationRejected() async throws {
        let root = try Fixture.makeRunRepo(
            evalsRaw: #"{"skill_name":"demo","evals":[{"id":"e1","prompt":"do","expectations":[]}]}"#
        )
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4)
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    @Test("A symlinked fixture is rejected before spend (exit 4), never followed")
    func symlinkFixtureRejected() async throws {
        let root = try Fixture.makeRunRepo(
            evalsRaw: #"{"skill_name":"demo","evals":[{"id":"e1","prompt":"do","expectations":["x"],"files":["fixtures/link"]}]}"#
        )
        defer { Fixture.remove(root) }
        let fixtures = root.appendingPathComponent("skills/demo/fixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixtures.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4)
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    @Test("An eval referencing its own answers (evaluations/evals.json) is rejected before spend (exit 4)")
    func evaluationsAnswerLeakRejected() async throws {
        let root = try Fixture.makeRunRepo(
            evalsRaw: #"{"skill_name":"demo","evals":[{"id":"e1","prompt":"do","expectations":["x"],"files":["evaluations/evals.json"]}]}"#
        )
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4)
        #expect(!FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    @Test("A fixture under evaluations/fixtures/ is allowed end-to-end (the allowlist doesn't over-reject)")
    func evaluationsFixtureAllowed() async throws {
        let root = try Fixture.makeRunRepo(
            evalsRaw: #"{"skill_name":"demo","evals":[{"id":"e1","prompt":"do","expectations":["x"],"files":["evaluations/fixtures/input.txt"]}]}"#
        )
        defer { Fixture.remove(root) }
        let fixtures = root.appendingPathComponent("skills/demo/evaluations/fixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        try "data".write(to: fixtures.appendingPathComponent("input.txt"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    /// The single paid path: a real `claude-code` run end-to-end. Opt-in (`SKILLET_LIVE_SMOKE=1`) so
    /// free CI never spends; it validates the live `run()` + injection + judge the replay path can't.
    @Test("Live claude-code smoke", .tags(.slow),
          .enabled(if: ProcessInfo.processInfo.environment["SKILLET_LIVE_SMOKE"] != nil))
    func liveSmoke() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--yes"])
        #expect(out.exitCode == 0 || out.exitCode == 1)   // it ran (not a probe/usage failure)
        #expect(FileManager.default.fileExists(atPath: benchmarkPath(root)))
    }

    /// **Can the grader tell two answers apart?** The failure this guards against is a grader that
    /// returns the same verdict for everything — every comparison would then read "no change", every
    /// edit would look safe, and the whole tool would be confidently useless while every offline test
    /// stayed green, because the stand-in grader is wired to give different verdicts.
    ///
    /// Asked **directly**, because that is a property of the grader. An earlier attempt inferred it from
    /// whether an edited skill scored better, which made the check depend on a model obeying an
    /// instruction on one sample — an assertion about the model, not about this program, and it went red
    /// twice while nothing was wrong. Here the same reply is put to two expectations: one it must meet
    /// and one it cannot. If both land the same way, grading is not discriminating.
    @Test("Live claude-code smoke: grading distinguishes a met expectation from an impossible one",
          .tags(.slow),
          .enabled(if: ProcessInfo.processInfo.environment["SKILLET_LIVE_SMOKE"] != nil))
    func liveGraderDiscriminates() async throws {
        let root = try Fixture.makeRunRepo(
            judgeModel: "sonnet",                // the alias a real claude binary accepts
            evalsRaw: #"""
            {"skill_name":"demo","evals":[
             {"id":"met","prompt":"Reply with exactly the single word: hello",
              "expectations":["the reply contains the word hello"]},
             {"id":"impossible","prompt":"Reply with exactly the single word: hello",
              "expectations":["the entire reply is written in Japanese script"]}]}
            """#)
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--yes", "--runs", "1", "--json"])
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any],
                                   "no machine-readable result: \(out.stderr)")
        let behavior = (payload["behavior"] as? [String: Any]) ?? payload
        let rows = try #require(behavior["evals"] as? [[String: Any]])
        let byId = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            (row["id"] as? String).map { ($0, row) }
        })
        // Recorded first: a grader that errored on both would otherwise read as "did not discriminate".
        #expect(byId["met"]?["recorded"] as? Int == 1, "the met expectation was never graded")
        #expect(byId["impossible"]?["recorded"] as? Int == 1, "the impossible expectation was never graded")
        #expect(byId["met"]?["passes"] as? Int == 1, "a reply saying hello must satisfy \"contains hello\"")
        #expect(byId["impossible"]?["passes"] as? Int == 0,
                "a reply saying hello cannot be entirely Japanese — a pass here means grading is not reading the answer")
    }

    /// **Two versions of a skill must be able to measure differently, offline.**
    ///
    /// The stand-in that answers instead of a model used to produce text from the question alone, and the
    /// stand-in grader decided pass or fail from the criterion's wording alone — so the same tests against
    /// two *different* versions of a skill always scored identically. That makes it impossible to check,
    /// without paying, a command whose job is to measure a skill, change it, and measure again. The
    /// answer now carries a marker taken from the skill, and a recorded verdict may be keyed on it.
    @Test("Editing a skill can change its measured result, with no model involved")
    func editedSkillMeasuresDifferently() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let skill = root.appendingPathComponent("skills/demo/SKILL.md")
        // Fails when the skill carries `before`, passes when it carries `after`. Same criterion both times.
        let map = try Fixture.writeReplayMap(["did the thing @ before": false,
                                              "did the thing @ after": true], in: root)

        var results: [Int32] = []
        for marker in ["before", "after"] {
            let body = try String(contentsOf: skill, encoding: .utf8)
                .replacingOccurrences(of: "\nreplay-marker: before", with: "")
                .replacingOccurrences(of: "\nreplay-marker: after", with: "")
            try (body + "\nreplay-marker: \(marker)\n").write(to: skill, atomically: true, encoding: .utf8)
            let out = try await SkilletHarness().run(
                ["-C", root.path, "run", "demo", "--replay", "--replay-map", map, "--yes"])
            results.append(out.exitCode)
        }
        #expect(results == [1, 0],
                "the same tests must fail against one version and pass against the other — got \(results)")
    }

    // MARK: - the hidden test-only options

    @Test("The offline switch is refused unless the suite enabled it")
    func replayRefusedWhenSeamsDisabled() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"],
                                                 environment: ["SKILLET_TEST_SEAMS": ""])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("--replay is a test-only option"))
    }

    /// The offline switch swaps real grading for a file of recorded answers, so a file outside the project
    /// must not be honoured.
    ///
    /// **It is refused rather than ignored, and that expectation flipped for a reason.** This used to
    /// require that an outside file be silently passed over, leaving every check to fail — which looks
    /// like safe behaviour and is not. Every check failing is indistinguishable from a run where the skill
    /// genuinely failed everything, and in the proving command it means both measurements fail
    /// identically, nothing scores lower than anything else, and the edit is declared proven with an
    /// offer to apply it. Reproduced end to end before the change. Refusing says what happened.
    @Test("A file of recorded answers outside the project is refused, not quietly passed over")
    func replayMapCannotEscapeTheProject() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["X"])]); defer { Fixture.remove(root) }
        let elsewhere = try Fixture.makeTempDirectory(); defer { Fixture.remove(elsewhere) }
        let outside = elsewhere.appendingPathComponent("map.json")
        try #"{"X": true}"#.write(to: outside, atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--replay", "--replay-map", outside.path])
        #expect(out.exitCode == 4, "named a file it cannot use, so it stops rather than grading on nothing")
        #expect(!out.stdout.contains("PASS"), "and nothing outside the project decided any result")
    }

    /// A relative name means "inside the project", the same as the draft file the proving command reads.
    /// It used to mean "relative to wherever you happened to be standing", so running from another folder
    /// looked somewhere else entirely — and, before the refusal above, said nothing when it found nothing.
    @Test("A relative name for recorded answers is found from any working directory")
    func replayMapIsProjectRelative() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["X"])]); defer { Fixture.remove(root) }
        _ = try Fixture.writeReplayMap(["X": true], in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--replay", "--replay-map", "replay-map.json"])
        #expect(out.exitCode == 0, "found inside the project, so the recorded pass is honoured: \(out.stderr)")
    }
}

/// **A results file that cannot be scored is refused before anything is spent, not carried forward.**
///
/// A run keeps whichever half of the results file it did not measure this time — copying it forward
/// unchanged is how measuring one thing cannot destroy the record of the other. The half being copied was
/// never checked, while the reader that scores the file refuses a count that is not a whole number or a
/// test named twice. So a file with either fault was carried straight through, the run finished
/// successfully, and what it left behind could not be scored by this tool's own reader.
///
/// Refused at the start rather than at the moment of writing, because writing happens after the
/// measurement — by then the money is spent, and refusing would throw the results away. Refused rather
/// than quietly dropped, because dropping loses the committed record of the half that did not run.
@Suite("A results file that cannot be scored stops the run before it costs anything", .tags(.integration))
struct CarriedRecordValidityTests {
    /// A project whose committed results file already holds an entry with the given count for its
    /// routing check — the half a behaviour-only run carries forward untouched.
    private func repoWithCommittedCount(_ runs: String) throws -> URL {
        let root = try Fixture.makeRunRepo()
        let record = root.appendingPathComponent("skills/demo/evaluations/benchmark.json")
        try #"""
        {"metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[],
         "consistency":{"k":1,"meaningful":false,"suite_pass_power_k":1,"flaky_eval_ids":[],
           "per_eval":[{"eval_id":"t","axis":"trigger","runs":\#(runs),"perfect_passes":1,
                        "pass_power_k":1,"flaky":false,"mean_pass_rate":1}]},
         "run_summary":{}}
        """#.write(to: record, atomically: true, encoding: .utf8)
        return root
    }

    @Test("A count that is not a whole number stops the run, naming the entry")
    func unscorableRecordStopsTheRun() async throws {
        let root = try repoWithCommittedCount("2.5"); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 4, "the file is not valid, and that is what stops it: \(out.stderr)")
        #expect(out.stderr.contains("2.5"), "and it says which value: \(out.stderr)")
    }

    /// **Nothing is overwritten by the refusal.** The point of stopping early is that the existing record
    /// survives for the person to correct, rather than being replaced by a run that could not use it.
    @Test("The existing file is left exactly as it was")
    func existingFileUntouched() async throws {
        let root = try repoWithCommittedCount("2.5"); defer { Fixture.remove(root) }
        let record = root.appendingPathComponent("skills/demo/evaluations/benchmark.json")
        let before = try String(contentsOf: record, encoding: .utf8)
        _ = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(try String(contentsOf: record, encoding: .utf8) == before)
    }

    /// **A file that is not a results file at all is replaced, and the run says so first.**
    ///
    /// Two situations that look alike are handled differently on purpose. A file that reads as a results
    /// file but holds something unscorable carries real history the person can repair, so it stops the
    /// run. A file that does not read as one carries no history to lose, and is replaced — deliberately,
    /// because refusing instead would let anyone stop every future run by dropping a broken file into
    /// place. What was missing was saying so: replacing it silently means the results for whichever half
    /// did not run this time disappear with no word.
    @Test("A file that is not a results file is announced before anything is spent",
          arguments: [#"["not","an","object"]"#, #""just a string""#, "not json at all"])
    func unreadableRecordIsAnnounced(contents: String) async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        try contents.write(to: root.appendingPathComponent("skills/demo/evaluations/benchmark.json"),
                           atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 0, "it heals rather than refusing: \(out.stderr)")
        #expect(out.stderr.contains("not a readable results file"),
                "and it says so before spending: \(out.stderr)")
        #expect(out.stderr.contains("will be lost"), "including what that costs")
    }

    /// An ordinary run says nothing of the sort — the note has to mean something when it appears.
    @Test("An ordinary run does not announce a replacement")
    func ordinaryRunSaysNothing() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(!out.stderr.contains("not a readable results file"))
    }

    /// The other half, so the check cannot be satisfied by refusing everything: an ordinary committed
    /// record still carries forward untouched, which is what it is there to do.
    @Test("An ordinary committed record still carries forward")
    func validRecordStillCarries() async throws {
        let root = try repoWithCommittedCount("2"); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 0, "\(out.stderr)")
        let after = try String(contentsOf: root.appendingPathComponent("skills/demo/evaluations/benchmark.json"),
                               encoding: .utf8)
        #expect(after.contains("\"axis\" : \"trigger\""), "the half that did not run this time is still there")
    }
}

/// **The two fields added this round are checked in the output people actually parse.**
///
/// Both were asserted only on the in-memory value, never on the text the command prints, so nothing
/// stopped a later change to how that text is written from dropping them silently. `pass_1_evals` says how
/// many checks the softer average covers — without it, excluding unmeasurable checks would quietly shrink
/// the basis of that figure with no way to tell. `ungraded` says how many attempts produced no result at
/// all, which is what explains a score resting on fewer attempts than were asked for.
@Suite("The run's machine-readable output carries the counts it now depends on", .tags(.integration))
struct RunOutputCountsTests {
    @Test("Both counts appear, and describe the run")
    func countsAppearInTheOutput() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["X"]), ("e2", ["Y"])])
        defer { Fixture.remove(root) }
        let map = try Fixture.writeReplayMap(["X": true, "Y": false], in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--replay", "--replay-map", map, "--runs", "2", "--json"])

        let payload = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any],
                                   "the run must print readable output: \(out.stdout)\(out.stderr)")
        #expect(payload["schema"] as? String == "skillet.run/1")
        #expect(payload["pass_1_evals"] as? Int == 2, "both checks were measured, so the average covers both")
        #expect(payload["ungraded"] as? Int == 0, "every attempt was graded on this run")
        // One check passes and one fails, so the softer average is a half — proving the field describes
        // this run rather than being a constant that happens to be present.
        #expect((payload["pass_1"] as? Double).map { abs($0 - 0.5) < 0.001 } == true,
                "pass_1 was \(String(describing: payload["pass_1"]))")
    }
}
