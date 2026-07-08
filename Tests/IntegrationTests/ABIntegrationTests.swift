import Testing
import Foundation

/// Drives `skillet run --ab` through the built binary over the hidden replay path: the with-arm
/// judges from the default all-pass map, the baseline arm from the fail-all default — so the paired
/// Δ is deterministic and positive without any live harness or model.
@Suite("skillet run --ab via the binary", .tags(.integration))
struct ABIntegrationTests {
    @Test("--ab end-to-end: ab JSON block, canonical two-arm benchmark, grading.json is with-arm only, exit 0")
    func abEndToEnd() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["did the thing"]), ("e2", ["did more"])])
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--ab", "--json"])
        #expect(out.exitCode == 0)   // the with-arm passes; a failing BASELINE is the point, not a failure
        #expect(out.stdout.contains(#""ab":"#))
        #expect(out.stdout.contains(#""paired_mean_delta":1"#))
        #expect(out.stdout.contains(#""flips_up":2"#))
        #expect(out.stdout.contains(#""polluted":0"#))
        let bench = try String(
            contentsOf: root.appendingPathComponent("skills/demo/evaluations/benchmark.json"), encoding: .utf8)
        #expect(bench.contains(#""with_skill""#))
        #expect(bench.contains(#""without_skill""#))
        #expect(bench.contains(#""delta""#))
        #expect(bench.contains(#""arm""#))
        #expect(!bench.contains(#""default""#))   // --ab runs use the canonical arm names throughout
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("skills/demo/evaluations/grading.json").path))
    }

    @Test("Human table: WITH/BASELINE/Δ columns and the paired footer with the flip tally")
    func abHumanTable() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["x"]), ("e2", ["y"])])
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--ab"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("BASELINE"))
        #expect(out.stdout.contains("skill effect (paired Δ pass rate):"))
        #expect(out.stdout.contains("flips 2↑ 0↓ of 2"))
    }

    @Test("--ab on a trigger-only run refuses before spend (exit 2, what/why/fix)")
    func abTriggerOnlyRefused() async throws {
        let root = try Fixture.makeRunRepo()
        defer { Fixture.remove(root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("skills/demo/evaluations/evals.json"))
        try #"[{"query":"do the demo thing","should_trigger":true}]"#.write(
            to: root.appendingPathComponent("skills/demo/evaluations/trigger-eval.json"),
            atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--ab"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("--ab"))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("skills/demo/evaluations/benchmark.json").path))   // nothing ran
    }

    @Test("--ab on a mixed run prints the single-arm trigger note on stderr and still passes")
    func abMixedNote() async throws {
        let root = try Fixture.makeRunRepo()
        defer { Fixture.remove(root) }
        try #"[{"query":"do the demo thing","should_trigger":true}]"#.write(
            to: root.appendingPathComponent("skills/demo/evaluations/trigger-eval.json"),
            atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--ab"])
        #expect(out.exitCode == 0)   // with-arm passes; trigger fires demo (canned trace) and passes
        #expect(out.stderr.contains("trigger axis runs single-arm"))
    }

    @Test("--ab --dry-run doubles behavioral trials and reports ab_baseline_trials (nothing spent)")
    func abDryRun() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["x"]), ("e2", ["y"])])
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--replay", "--ab", "--dry-run", "--json", "--runs", "3"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains(#""trials":12"#))              // 2 evals × 3 runs × 2 arms
        #expect(out.stdout.contains(#""ab_baseline_trials":6"#))
        #expect(out.stdout.contains(#""estimated_calls":24"#))     // both arms are judged: 12 × 2
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("skills/demo/evaluations/benchmark.json").path))
    }

    @Test("--replay-baseline-map overrides the fail-all baseline: both arms pass → Δ 0, no flips")
    func baselineMapOverrides() async throws {
        let root = try Fixture.makeRunRepo(evals: [("e1", ["x"])])
        defer { Fixture.remove(root) }
        let mapURL = root.appendingPathComponent("baseline-map.json")
        try #"{"x":true}"#.write(to: mapURL, atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--replay", "--ab", "--json", "--replay-baseline-map", mapURL.path])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains(#""paired_mean_delta":0"#))
        #expect(out.stdout.contains(#""flips_up":0"#))
    }
}
