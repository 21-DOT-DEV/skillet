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
    }

    @Test("run writes .skillet/.gitignore so the cache stays ignored even without a prior init")
    func cacheGitignored() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 0)
        let ignore = root.appendingPathComponent(".skillet/.gitignore")
        #expect(FileManager.default.fileExists(atPath: ignore.path))
        #expect((try? String(contentsOf: ignore, encoding: .utf8)) == "*\n")
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
}
