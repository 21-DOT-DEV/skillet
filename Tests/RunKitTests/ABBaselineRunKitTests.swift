import Testing
import Foundation
import EDDCore
import TraceKit
import HarnessKit
import JudgeKit
@testable import RunKit

@Suite("RunKit — A/B baseline arm (F15)")
struct ABBaselineRunKitTests {
    private func makeSkill() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("references"), withIntermediateDirectories: true)
        try "---\nname: demo\n---\nbody".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return dir
    }
    private func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func evalCase(_ id: String, expectations: [String]) -> EvalCase {
        EvalCase(fields: ["id": .string(id), "prompt": .string("go"), "expectations": .array(expectations.map(JSONValue.string))])
    }

    /// Ignores the arm — serves the skill-firing canned trace even for `.none`. Simulates broken
    /// isolation (a harness whose no-skills switch silently stopped working).
    struct PollutingAdapter: HarnessAdapter {
        let id: HarnessID = "polluting"
        let capabilities: HarnessCapabilities = [.runTask, .traceParsing, .baselineIsolation]
        func probe(strict: Bool) async throws -> HarnessInfo { HarnessInfo(id: id, version: "x", authenticated: true, available: true) }
        func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace { RawTrace(harness: id, raw: "x") }
        func parseTrace(_ raw: RawTrace) throws -> Trace { ReplayAdapter.cannedTrace }   // fires "demo" — pollution
        func verifyBaselineIsolation() async throws {}
    }

    /// Counts judge calls — proves polluted trials are never judged (no spend on unmeasurable trials).
    actor JudgeCallCounter {
        private(set) var count = 0
        func bump() { count += 1 }
    }
    struct CountingJudge: Judge {
        let counter: JudgeCallCounter
        func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict {
            await counter.bump()
            return Verdict(criterion: criterion, passed: false, rationale: "r", judgeId: "j", model: "m", judgePromptVersion: "v")
        }
    }

    @Test("Baseline sandboxes stage fixtures but never the skill (stageSkill: false)")
    func baselineStagesNoSkill() throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        try FileManager.default.createDirectory(at: skill.appendingPathComponent("fixtures"), withIntermediateDirectories: true)
        try "data".write(to: skill.appendingPathComponent("fixtures/in.csv"), atomically: true, encoding: .utf8)
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let ws = try WorkspaceManager().prepare(skill: SkillRef(name: "demo", path: skill.path),
                                                files: ["fixtures/in.csv"], base: base, label: "t0", stageSkill: false)
        #expect(!FileManager.default.fileExists(atPath: ws.root.appendingPathComponent(".claude").path))     // no skill at all
        #expect(FileManager.default.fileExists(atPath: ws.root.appendingPathComponent("fixtures/in.csv").path))   // inputs still staged
    }

    @Test("runBaseline: clean arm-aware adapter → judged trials with durations, forensics under base/baseline/")
    func baselineRunsClean() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let results = await Runner(adapter: ReplayAdapter(), judge: ReplayJudge([:], defaultPass: false))
            .runBaseline(skill: SkillRef(name: "demo", path: skill.path),
                         evals: [evalCase("e", expectations: ["a"])], k: 2, base: base)
        #expect(results[0].recorded == 2)
        #expect(results[0].polluted == 0)   // the replay double is arm-aware: no skill fires on .none
        #expect(results[0].passes == 0)     // fail-all baseline judge
        #expect(results[0].trials[0].durationSeconds != nil)
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("baseline/eval-0/trial-0/trace.json").path))
    }

    @Test("The §9.2 tripwire: a skill firing on a baseline trial → polluted, never judged")
    func tripwireDisqualifies() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let counter = JudgeCallCounter()
        let results = await Runner(adapter: PollutingAdapter(), judge: CountingJudge(counter: counter))
            .runBaseline(skill: SkillRef(name: "demo", path: skill.path),
                         evals: [evalCase("e", expectations: ["a"])], k: 2, base: base)
        #expect(results[0].polluted == 2)
        #expect(results[0].measured == 0)
        #expect(results[0].trials[0].exit == .polluted)
        #expect(await counter.count == 0)   // polluted trials never reach the judge
    }

    @Test("The with-arm loop records durations too (the time Δ needs both sides)")
    func withArmDurations() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: ReplayJudge(["a": true]))
            .run(skill: SkillRef(name: "demo", path: skill.path),
                 evals: [evalCase("e", expectations: ["a"])], k: 1, injection: .ambient, base: base)
        #expect(outcome.evals[0].trials[0].durationSeconds != nil)
        #expect((outcome.evals[0].trials[0].durationSeconds ?? -1) >= 0)
    }

    /// Sleeps long, then throws — the reviewed path: harness fast, judge slow AND failing.
    struct SlowThrowingJudge: Judge {
        struct Boom: Error {}
        func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict {
            try? await Task.sleep(for: .milliseconds(500))
            throw Boom()
        }
    }

    @Test("durationSeconds is harness-only: a slow failing judge never leaks into the time Δ (review round 2)")
    func slowJudgeExcludedFromDuration() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: SlowThrowingJudge())
            .run(skill: SkillRef(name: "demo", path: skill.path),
                 evals: [evalCase("e", expectations: ["a"])], k: 1, injection: .ambient, base: base)
        #expect(outcome.evals[0].trials[0].exit == .failed)                  // judge threw → ungraded
        #expect((outcome.evals[0].trials[0].durationSeconds ?? 999) < 0.4)   // the 500ms judge sleep is excluded
    }

    @Test("The with-arm loop never trips the pollution wire (skill invocations are the point there)")
    func withArmUnaffectedByTripwire() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        // ReplayAdapter's with-arm canned trace fires "demo" — must still grade normally.
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: ReplayJudge(["a": true]))
            .run(skill: SkillRef(name: "demo", path: skill.path),
                 evals: [evalCase("e", expectations: ["a"])], k: 1, injection: .ambient, base: base)
        #expect(outcome.evals[0].trials[0].exit == .passed)
        #expect(outcome.evals[0].polluted == 0)
    }
}
