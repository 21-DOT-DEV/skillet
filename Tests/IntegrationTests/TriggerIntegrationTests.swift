import Testing
import Foundation

/// `skillet run --axis` against the built binary via the replay seam (the canned trace always fires
/// `demo`): the F14 contract — deterministic fired/not-fired, separate reporting, per-axis
/// benchmark.json merge, and the shared error classes.
@Suite("trigger axis integration", .tags(.integration))
struct TriggerIntegrationTests {
    private func writeTriggerEvals(_ root: URL, cases: String = #"[{"query":"fire it","should_trigger":true},{"query":"near miss","should_trigger":false}]"#) throws {
        try cases.write(
            to: root.appendingPathComponent("skills/demo/evaluations/trigger-eval.json"),
            atomically: true, encoding: .utf8
        )
    }

    @Test("--axis trigger: deterministic PASS for should_trigger, FAIL for the near-miss (exit 1)")
    func triggerAxisRuns() async throws {
        let root = try Fixture.makeRunRepo()
        defer { Fixture.remove(root) }
        try writeTriggerEvals(root)
        let out = try await SkilletHarness().run(["run", "demo", "--axis", "trigger", "--replay", "--runs", "2", "-C", root.path, "--color", "never"])
        #expect(out.exitCode == 1)                                   // near-miss fires → measured failure
        #expect(out.stdout.contains("trigger"))
        #expect(out.stdout.contains("trigger-0"))
        #expect(!out.stdout.contains("behavior —"))                  // separate axes: no behavioral section
    }

    @Test("--axis trigger with only should_trigger:true cases passes (exit 0), grading.json untouched")
    func triggerOnlyCleanRun() async throws {
        let root = try Fixture.makeRunRepo()
        defer { Fixture.remove(root) }
        try writeTriggerEvals(root, cases: #"[{"query":"fire","should_trigger":true}]"#)
        let out = try await SkilletHarness().run(["run", "demo", "--axis", "trigger", "--replay", "-C", root.path])
        #expect(out.exitCode == 0)
        let evalDir = root.appendingPathComponent("skills/demo/evaluations")
        #expect(!FileManager.default.fileExists(atPath: evalDir.appendingPathComponent("grading.json").path))
        let benchmark = try String(contentsOf: evalDir.appendingPathComponent("benchmark.json"), encoding: .utf8)
        #expect(benchmark.contains(#""configuration" : "trigger""#))
        #expect(benchmark.contains(#""axis" : "trigger""#))
    }

    @Test("Per-axis merge: a behavioral run then --axis trigger keeps both in benchmark.json")
    func benchmarkAxisMerge() async throws {
        let root = try Fixture.makeRunRepo()
        defer { Fixture.remove(root) }
        try writeTriggerEvals(root, cases: #"[{"query":"fire","should_trigger":true}]"#)
        _ = try await SkilletHarness().run(["run", "demo", "--axis", "behavior", "--replay", "-C", root.path])
        let out = try await SkilletHarness().run(["run", "demo", "--axis", "trigger", "--replay", "-C", root.path])
        #expect(out.exitCode == 0)
        let benchmark = try String(contentsOf: root.appendingPathComponent("skills/demo/evaluations/benchmark.json"), encoding: .utf8)
        #expect(benchmark.contains(#""configuration" : "default""#))    // behavioral rows preserved
        #expect(benchmark.contains(#""configuration" : "trigger""#))    // trigger rows added
        #expect(benchmark.contains(#""suite_pass_power_k""#))
        #expect(benchmark.contains(#""trigger_suite_pass_power_k""#))
    }

    @Test("--axis all runs both axes where files exist; --json carries the additive trigger block")
    func axisAllBothSections() async throws {
        let root = try Fixture.makeRunRepo()
        defer { Fixture.remove(root) }
        try writeTriggerEvals(root, cases: #"[{"query":"fire","should_trigger":true}]"#)
        let out = try await SkilletHarness().run(["run", "demo", "--replay", "--json", "-C", root.path])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains(#""schema":"skillet.run/1""#))
        #expect(out.stdout.contains(#""trigger":{"#))
        let human = try await SkilletHarness().run(["run", "demo", "--replay", "-C", root.path, "--color", "never"])
        #expect(human.stdout.contains("behavior —"))
        #expect(human.stdout.contains("trigger —"))
    }

    @Test("Default axis skips an absent trigger-eval.json (unchanged behavioral runs)")
    func absentTriggerFileSkipped() async throws {
        let root = try Fixture.makeRunRepo()
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["run", "demo", "--replay", "--json", "-C", root.path])
        #expect(out.exitCode == 0)
        #expect(!out.stdout.contains(#""trigger""#))
        // Specs/009 A4: the skip is loud — a stderr note, so machine stdout stays untouched.
        #expect(out.stderr.contains("trigger axis skipped"))
    }

    @Test("--dry-run previews trigger trials in the plan (human + skillet.run-plan/1)")
    func dryRunPreview() async throws {
        let root = try Fixture.makeRunRepo()
        defer { Fixture.remove(root) }
        try writeTriggerEvals(root)
        let human = try await SkilletHarness().run(["run", "demo", "--dry-run", "--replay", "--runs", "2", "-C", root.path])
        #expect(human.exitCode == 0)
        #expect(human.stdout.contains("2 trigger case(s) × k=2"))
        // 1 eval × 2 trials × 2 calls + 2 cases × 2 trials × 1 call = 8 (gate stays trial-based).
        #expect(human.stdout.contains("≈ 8 model call(s)"))
        let json = try await SkilletHarness().run(["run", "demo", "--dry-run", "--replay", "--json", "--runs", "2", "-C", root.path])
        #expect(json.stdout.contains(#""schema":"skillet.run-plan/1""#))
        #expect(json.stdout.contains(#""trigger_cases":2"#))
        #expect(json.stdout.contains(#""estimated_calls":8"#))
    }

    /// A repo whose skill has ONLY trigger tests — no evals.json at all (review round 1, finding 1).
    private func makeTriggerOnlyRepo() throws -> URL {
        let root = try Fixture.makeTempDirectory()
        try "project:\n  skills_root: skills\n".write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let dir = root.appendingPathComponent("skills/demo/evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a trigger-only demo skill\n---\nBody.\n"
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        try #"[{"query":"fire","should_trigger":true}]"#
            .write(to: dir.appendingPathComponent("trigger-eval.json"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("A trigger-only skill (no evals.json) runs: explicit axis and default both work, name recorded")
    func triggerOnlySkillRuns() async throws {
        let root = try makeTriggerOnlyRepo()
        defer { Fixture.remove(root) }
        let explicit = try await SkilletHarness().run(["run", "demo", "--axis", "trigger", "--replay", "-C", root.path])
        #expect(explicit.exitCode == 0)                              // L009 must not block (finding 1)
        let benchmark = try String(contentsOf: root.appendingPathComponent("skills/demo/evaluations/benchmark.json"), encoding: .utf8)
        #expect(benchmark.contains(#""skill_name" : "demo""#))       // never "unknown" (finding 2)
        let defaulted = try await SkilletHarness().run(["run", "demo", "--replay", "-C", root.path])
        #expect(defaulted.exitCode == 0)                             // default = each axis where its file exists
        // The suggestion names only what was written: no grading.json exists on a trigger-only run.
        #expect(defaulted.stdout.contains("commit evaluations/benchmark.json"))
        #expect(!defaulted.stdout.contains("+ grading.json"))
    }

    @Test("An EMPTY evals.json skips the behavioral axis under default mode (round 5 — skeleton-friendly)")
    func emptyEvalsSkipsBehavioralAxis() async throws {
        let root = try Fixture.makeRunRepo(evalsRaw: #"{"skill_name":"demo","evals":[]}"#)
        defer { Fixture.remove(root) }
        try writeTriggerEvals(root, cases: #"[{"query":"fire","should_trigger":true}]"#)
        let out = try await SkilletHarness().run(["run", "demo", "--replay", "-C", root.path])
        #expect(out.exitCode == 0)                                   // trigger runs; nothing refuses
        #expect(out.stderr.contains("behavioral axis skipped"))
        // Explicitly requesting the empty axis is still an error — you asked for nothing to run.
        let explicit = try await SkilletHarness().run(["run", "demo", "--axis", "behavior", "--replay", "-C", root.path])
        #expect(explicit.exitCode == 2)
    }

    @Test("Trigger-only runs still refuse a lint-broken SKILL.md (description too long → exit 2)")
    func triggerOnlyStillLintGated() async throws {
        let root = try makeTriggerOnlyRepo()
        defer { Fixture.remove(root) }
        try "---\nname: demo\ndescription: \(String(repeating: "x", count: 1100))\n---\nBody.\n"
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["run", "demo", "--axis", "trigger", "--replay", "-C", root.path])
        #expect(out.exitCode == 2)                                   // description quality gates every axis
        #expect(out.stdout.contains("SKILL-L001"))
    }

    @Test("--axis trigger without the file is usage (2); a corrupt file is artifact (4)")
    func errorClasses() async throws {
        let root = try Fixture.makeRunRepo()
        defer { Fixture.remove(root) }
        let missing = try await SkilletHarness().run(["run", "demo", "--axis", "trigger", "--replay", "-C", root.path])
        #expect(missing.exitCode == 2)
        try writeTriggerEvals(root, cases: "{not an array}")
        let corrupt = try await SkilletHarness().run(["run", "demo", "--axis", "trigger", "--replay", "-C", root.path])
        #expect(corrupt.exitCode == 4)
        // A junk (non-object) element is invalid too — never silently dropped, and never allowed to
        // shift the positional case ids of the survivors (round 4, finding 1).
        try writeTriggerEvals(root, cases: #"[123, {"query":"fire","should_trigger":true}]"#)
        let junk = try await SkilletHarness().run(["run", "demo", "--axis", "trigger", "--replay", "-C", root.path])
        #expect(junk.exitCode == 4)
        #expect(junk.stderr.contains("element #0 is not an object"))
    }
}
