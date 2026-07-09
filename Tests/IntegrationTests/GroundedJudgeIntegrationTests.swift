import Testing
import Foundation

/// Drives `skillet run --judge grounded-judge` through the built binary over the hidden replay path:
/// proves the selector is accepted and plumbed, the capture path runs, and the cost note prints. The
/// grounded grader's *behavior* is unit-tested (JudgeKit/RunKit); under replay the actual judge is the
/// deterministic replay judge, so the committed `judge.id` here is `replay` (the real grader) — the
/// grounded id flowing into committed records is unit-tested in EDDCore.
@Suite("skillet run --judge via the binary", .tags(.integration))
struct GroundedJudgeIntegrationTests {
    @Test("--judge grounded-judge runs green and prints the cost note on stderr")
    func groundedSelected() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--judge", "grounded-judge"])
        #expect(out.exitCode == 0)
        #expect(out.stderr.contains("grounded judge includes file contents"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("skills/demo/evaluations/benchmark.json").path))
    }

    @Test("The default (text-judge) prints no grounded cost note and is unchanged")
    func defaultNoNote() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay"])
        #expect(out.exitCode == 0)
        #expect(!out.stderr.contains("grounded judge includes file contents"))
    }

    @Test("An unknown --judge id is a usage error (exit 2) listing the valid ids")
    func unknownJudge() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--judge", "bogus"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("grounded-judge"))
    }

    @Test("--judge grounded-judge on a trigger-only run notes it has no effect (behavioral-only), not silence")
    func groundedOnTriggerOnlyNotes() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        // Make it trigger-only: drop evals.json, add a trigger file.
        try FileManager.default.removeItem(at: root.appendingPathComponent("skills/demo/evaluations/evals.json"))
        try #"[{"query":"do the demo thing","should_trigger":true}]"#.write(
            to: root.appendingPathComponent("skills/demo/evaluations/trigger-eval.json"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--judge", "grounded-judge"])
        #expect(out.exitCode == 0)
        #expect(out.stderr.contains("applies to behavioral evals; none are running"))
        #expect(!out.stderr.contains("higher per-call cost"))   // no cost note when it isn't used
    }

    @Test("--judge grounded-judge --json still emits the skillet.run/1 payload")
    func groundedJSON() async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--judge", "grounded-judge", "--json"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains(#""schema":"skillet.run/1""#))
    }
}
