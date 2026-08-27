import Testing
import Foundation
import EDDCore
import TraceKit
import HarnessKit
import JudgeKit
import ProjectKit   // SafeFile — the confinement helpers now live here (F17)
@testable import RunKit

@Suite("RunKit")
struct RunKitTests {
    // MARK: - helpers

    /// A throwaway skill directory: SKILL.md + references/ + an evaluations/ that must NEVER be staged.
    /// `tokens` states, in the skill's own file, what the offline stand-in should report the model read
    /// and wrote — four numbers, or nothing stated and nothing counted.
    private func makeSkill(tokens: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("references"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("evaluations"), withIntermediateDirectories: true)
        let counts = tokens.map { "replay-tokens: \($0)\n" } ?? ""
        try "---\nname: demo\n---\n\(counts)body".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "guidance".write(to: dir.appendingPathComponent("references/guide.md"), atomically: true, encoding: .utf8)
        try "[]".write(to: dir.appendingPathComponent("evaluations/evals.json"), atomically: true, encoding: .utf8)
        return dir
    }

    private func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    private func evalCase(_ id: String, expectations: [String]) -> EvalCase {
        EvalCase(fields: ["id": .string(id), "prompt": .string("go"), "expectations": .array(expectations.map(JSONValue.string))])
    }

    /// Adapter that always throws a chosen failure — to exercise exit classification.
    struct ThrowingAdapter: HarnessAdapter {
        enum Mode: Sendable { case timeout, executionFailed }
        let id: HarnessID = "throwing"
        let capabilities: HarnessCapabilities = [.runTask]
        let mode: Mode
        func probe(strict: Bool) async throws -> HarnessInfo { HarnessInfo(id: id, version: "x", authenticated: true, available: true) }
        func parseTrace(_ raw: RawTrace) throws -> Trace { ReplayAdapter.cannedTrace }
        func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
            switch mode {
            case .timeout: throw ProcessError.timedOut(after: .seconds(1))
            case .executionFailed: throw HarnessError.executionFailed(harness: "x", exitCode: 1, stderr: "boom")
            }
        }
    }

    /// Judge that always throws — to prove the harness's raw output survives a judge failure.
    struct ThrowingJudge: Judge {
        struct Boom: Error {}
        func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict { throw Boom() }
    }

    /// Records the args a judge runner is shelled with.
    actor FakeRunLauncher: ProcessLauncher {
        let output: ProcessOutput
        private(set) var arguments: [String] = []
        init(output: ProcessOutput) { self.output = output }
        func run(_ executable: String, _ arguments: [String], workingDirectory: String?, timeout: Duration?, environment: [String: String]?, outputLimitBytes: Int?) async throws -> ProcessOutput {
            self.arguments = arguments
            return output
        }
    }

    /// Adapter that writes a file into the workspace during run() — so the post-run listing is non-empty.
    struct FileCreatingAdapter: HarnessAdapter {
        let id: HarnessID = "filemaker"
        let capabilities: HarnessCapabilities = [.runTask, .traceParsing]
        let filename: String
        func probe(strict: Bool) async throws -> HarnessInfo { HarnessInfo(id: id, version: "x", authenticated: true, available: true) }
        func parseTrace(_ raw: RawTrace) throws -> Trace { ReplayAdapter.cannedTrace }
        func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
            try "data".write(to: workspace.root.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            return RawTrace(harness: id, raw: "made \(filename)")
        }
    }

    /// Judge that decides purely from the evidence the runner hands it — proving the runner actually
    /// gathers + passes the post-run workspace listing (a criterion-keyed canned verdict can't show that).
    struct EvidenceAssertingJudge: Judge {
        let expectFile: String
        func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict {
            let present = evidence.workspaceListing.contains(expectFile)
            return Verdict(criterion: criterion, passed: present, rationale: present ? "listing has \(expectFile)" : "absent",
                           judgeId: "evidence", model: "x", judgePromptVersion: "1")
        }
    }

    // MARK: - workspace lifecycle

    @Test("Staging copies SKILL.md + references but NEVER evaluations/ (the model can't see the answers)")
    func stagingExcludesEvaluations() throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let wm = WorkspaceManager()
        let ws = try wm.prepare(skill: SkillRef(name: "demo", path: skill.path), files: [], base: base, label: "t0")
        let staged = ws.root.appendingPathComponent(".claude/skills/demo")
        #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("references/guide.md").path))
        #expect(!FileManager.default.fileExists(atPath: staged.appendingPathComponent("evaluations").path))   // never staged
        try wm.destroy(ws)
        #expect(!FileManager.default.fileExists(atPath: ws.root.path))
    }

    @Test("resolveFixture allowlist: fixtures/** + evaluations/fixtures/** allowed; other evaluations/** + escapes + hidden rejected")
    func resolveFixtureBase() {
        let skillDir = URL(fileURLWithPath: "/skills/demo")
        // Allowed namespaces — staged at their declared path.
        #expect(WorkspaceManager.resolveFixture("fixtures/x.csv", skillDir: skillDir)?.sandboxRelativePath == "fixtures/x.csv")
        #expect(WorkspaceManager.resolveFixture("evaluations/fixtures/x.csv", skillDir: skillDir)?.sandboxRelativePath == "evaluations/fixtures/x.csv")
        #expect(WorkspaceManager.resolveFixture("data/input.csv", skillDir: skillDir)?.sandboxRelativePath == "data/input.csv")
        // Private evaluations/ artifacts — rejected (only evaluations/fixtures/** is visible).
        #expect(WorkspaceManager.resolveFixture("evaluations/evals.json", skillDir: skillDir) == nil)
        #expect(WorkspaceManager.resolveFixture("evaluations/benchmark.json", skillDir: skillDir) == nil)
        #expect(WorkspaceManager.resolveFixture("evaluations/sessions/s1.json", skillDir: skillDir) == nil)
        #expect(WorkspaceManager.resolveFixture("evaluations", skillDir: skillDir) == nil)
        // Escapes + hidden — rejected.
        #expect(WorkspaceManager.resolveFixture("/abs/y.csv", skillDir: skillDir) == nil)        // absolute
        #expect(WorkspaceManager.resolveFixture("../../etc/passwd", skillDir: skillDir) == nil)  // traversal
        #expect(WorkspaceManager.resolveFixture("a/../b.csv", skillDir: skillDir) == nil)        // any .. component
        #expect(WorkspaceManager.resolveFixture("fixtures/.env", skillDir: skillDir) == nil)     // hidden component
        #expect(WorkspaceManager.resolveFixture("", skillDir: skillDir) == nil)                  // empty
    }

    @Test("firstSymlinkOnPath flags a symlinked component between base and target (confines skill/evaluations I/O)")
    func firstSymlinkOnPath() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("real/sub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("real"))
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("real/sub")) == nil)    // every component real
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("link/sub")) != nil)    // crosses a symlink
    }

    @Test("fixtures/ falls back to evaluations/fixtures/ as the physical source, staged as fixtures/")
    func fixtureFallback() throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        try FileManager.default.createDirectory(at: skill.appendingPathComponent("evaluations/fixtures"), withIntermediateDirectories: true)
        try "in".write(to: skill.appendingPathComponent("evaluations/fixtures/input.txt"), atomically: true, encoding: .utf8)
        let resolved = WorkspaceManager.resolveFixture("fixtures/input.txt", skillDir: skill)
        #expect(resolved?.sandboxRelativePath == "fixtures/input.txt")                              // staged as fixtures/…
        #expect(resolved?.source.path.hasSuffix("evaluations/fixtures/input.txt") == true)          // physical source under evaluations/
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let ws = try WorkspaceManager().prepare(skill: SkillRef(name: "demo", path: skill.path), files: ["fixtures/input.txt"], base: base, label: "t0")
        #expect(FileManager.default.fileExists(atPath: ws.root.appendingPathComponent("fixtures/input.txt").path))
    }

    @Test("Nested hidden files (references/.env, agents/.git/config) are never staged into the bundle")
    func nestedHiddenExcluded() throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        try "SECRET=x".write(to: skill.appendingPathComponent("references/.env"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: skill.appendingPathComponent("agents/.git"), withIntermediateDirectories: true)
        try "gitcfg".write(to: skill.appendingPathComponent("agents/.git/config"), atomically: true, encoding: .utf8)
        try "agent".write(to: skill.appendingPathComponent("agents/a.md"), atomically: true, encoding: .utf8)
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let ws = try WorkspaceManager().prepare(skill: SkillRef(name: "demo", path: skill.path), files: [], base: base, label: "t0")
        let staged = ws.root.appendingPathComponent(".claude/skills/demo")
        #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("references/guide.md").path))   // normal nested file kept
        #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("agents/a.md").path))           // normal nested file kept
        #expect(!FileManager.default.fileExists(atPath: staged.appendingPathComponent("references/.env").path))      // nested hidden excluded
        #expect(!FileManager.default.fileExists(atPath: staged.appendingPathComponent("agents/.git").path))          // nested hidden dir excluded
    }

    @Test("Staging resolves files[] against the skill dir and preserves relative structure")
    func stagesFixturesWithStructure() throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        try FileManager.default.createDirectory(at: skill.appendingPathComponent("fixtures"), withIntermediateDirectories: true)
        try "data".write(to: skill.appendingPathComponent("fixtures/input.csv"), atomically: true, encoding: .utf8)
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let ws = try WorkspaceManager().prepare(skill: SkillRef(name: "demo", path: skill.path),
                                                files: ["fixtures/input.csv"], base: base, label: "t0")
        #expect(FileManager.default.fileExists(atPath: ws.root.appendingPathComponent("fixtures/input.csv").path))
    }

    @Test("Staging keeps non-standard bundle dirs (agents/) but never evaluations/ or hidden (.env/.skillet)")
    func stagingDenylistAndHidden() throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        try FileManager.default.createDirectory(at: skill.appendingPathComponent("agents"), withIntermediateDirectories: true)
        try "sub".write(to: skill.appendingPathComponent("agents/a.md"), atomically: true, encoding: .utf8)
        try "SECRET=x".write(to: skill.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: skill.appendingPathComponent(".skillet"), withIntermediateDirectories: true)
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let ws = try WorkspaceManager().prepare(skill: SkillRef(name: "demo", path: skill.path), files: [], base: base, label: "t0")
        let staged = ws.root.appendingPathComponent(".claude/skills/demo")
        #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("agents/a.md").path))   // non-standard bundle dir kept (fidelity)
        #expect(!FileManager.default.fileExists(atPath: staged.appendingPathComponent(".env").path))         // hidden secret excluded
        #expect(!FileManager.default.fileExists(atPath: staged.appendingPathComponent(".skillet").path))     // run artifact excluded
        #expect(!FileManager.default.fileExists(atPath: staged.appendingPathComponent("evaluations").path))  // answers excluded
    }

    @Test("resolveFixture rejects a symlinked fixture or a fixture dir containing a symlink (no follow)")
    func resolveFixtureRejectsSymlink() throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        try FileManager.default.createDirectory(at: skill.appendingPathComponent("fixtures"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: skill.appendingPathComponent("fixtures/link"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        #expect(WorkspaceManager.resolveFixture("fixtures/link", skillDir: skill) == nil)   // symlinked file rejected
        #expect(WorkspaceManager.resolveFixture("fixtures", skillDir: skill) == nil)        // dir containing a symlink rejected
    }

    @Test("Staging never copies a symlinked bundle entry (would expose its target)")
    func stagingSkipsSymlinkEntry() throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        try FileManager.default.createSymbolicLink(at: skill.appendingPathComponent("secret"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let ws = try WorkspaceManager().prepare(skill: SkillRef(name: "demo", path: skill.path), files: [], base: base, label: "t0")
        #expect(!FileManager.default.fileExists(atPath: ws.root.appendingPathComponent(".claude/skills/demo/secret").path))
        #expect(SafeFile.firstSymlink(in: skill) != nil)   // the helper detects it (preflight fails loud on it)
    }

    @Test("listing() returns produced files as ground truth, excluding the injected .claude tree")
    func listingGroundTruth() throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let wm = WorkspaceManager()
        let ws = try wm.prepare(skill: SkillRef(name: "demo", path: skill.path), files: [], base: base, label: "t0")
        try "result".write(to: ws.root.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)   // the run "produces" a file
        let listing = wm.listing(ws).files
        #expect(listing.contains("report.md"))
        #expect(!listing.contains { $0.hasPrefix(".claude") })   // injected skill is not "produced"
    }

    // MARK: - the run loop

    @Test("The run loop aggregates pass^k end-to-end with the replay adapter + replay judge")
    func runLoopAggregates() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let runner = Runner(adapter: ReplayAdapter(), judge: ReplayJudge(["a": true, "b": false]))
        let outcome = try await runner.run(
            skill: SkillRef(name: "demo", path: skill.path),
            evals: [evalCase("good", expectations: ["a"]), evalCase("bad", expectations: ["b"])],
            k: 2, injection: .ambient, base: base
        )
        #expect(outcome.report.observedK == 2)
        #expect(outcome.report.passed == 1)    // "good" passed both trials
        #expect(outcome.report.failed == 1)    // "bad" failed both
        #expect(outcome.report.passK == 0.5)
        // The deletable cache keeps per-trial forensics; the bulky sandbox is torn down by default.
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("eval-0/trial-0/trace.json").path))
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("eval-0/trial-0/verdicts.json").path))
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("eval-0/trial-0/workspace").path))
    }

    /// **What a failed attempt cost is still recorded.** Grading happens after the model has replied and
    /// its reply has been read, so an attempt whose grading fails has real, measured token counts sitting
    /// in hand. Those were being discarded, and the totals every run reports are built from what this
    /// returns — so the money that attempt cost vanished from every figure. Providers charge for what a
    /// request consumed whether or not it succeeded, and a failed attempt is precisely where spending
    /// goes unnoticed.
    @Test("An attempt whose grading fails still reports what it cost")
    func failedGradingStillReportsCost() async throws {
        let skill = try makeSkill(tokens: "100 200 50 25"); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: ThrowingJudge())
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [evalCase("e", expectations: ["a"])],
                 k: 1, injection: .ambient, base: base)
        let trial = try #require(outcome.evals.first?.trials.first)
        #expect(trial.exit == .error, "grading threw, so the attempt is not a graded result")
        #expect(trial.tokens?.total == 375, "and it still cost 100 + 200 + 50 + 25")
    }

    /// The other half: an attempt that never got a reply has nothing to report, and must not invent it.
    @Test("An attempt that never got a reply reports no cost")
    func unstartedAttemptReportsNoCost() async throws {
        let skill = try makeSkill(tokens: "100 200 50 25"); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let outcome = try await Runner(adapter: ThrowingAdapter(mode: .executionFailed), judge: ThrowingJudge())
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [evalCase("e", expectations: ["a"])],
                 k: 1, injection: .ambient, base: base)
        #expect(outcome.evals.first?.trials.first?.tokens == nil,
                "nothing ran, so there is nothing to have cost")
    }

    @Test("A judge failure still persists the raw harness output (forensics not dropped on error)")
    func forensicsSurviveJudgeFailure() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: ThrowingJudge())
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [evalCase("e", expectations: ["a"])],
                 k: 1, injection: .ambient, base: base)
        #expect(outcome.report.evals.first?.status == .fail)   // judge threw → ungraded → FAIL, no vacuous pass
        // The harness produced output before judging threw; the cache must still hold it for debugging.
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("eval-0/trial-0/raw.jsonl").path))
    }

    @Test("--keep-workspace retains the per-trial sandbox for debugging")
    func keepWorkspace() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try await Runner(adapter: ReplayAdapter(), judge: ReplayJudge(["a": true]))
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [evalCase("e", expectations: ["a"])],
                 k: 1, injection: .ambient, base: base, keepWorkspace: true)
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("eval-0/trial-0/workspace/.claude/skills/demo/SKILL.md").path))
    }

    @Test("A harness timeout is a result; a non-zero exit is an attempt that never got graded")
    func exitClassification() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let ref = SkillRef(name: "demo", path: skill.path)
        let evals = [evalCase("e", expectations: ["a"])]

        let timedOut = try await Runner(adapter: ThrowingAdapter(mode: .timeout), judge: ReplayJudge(["a": true]))
            .run(skill: ref, evals: evals, k: 1, injection: .ambient, base: base)
        #expect(timedOut.evals[0].trials[0].exit == .timeout)
        #expect(timedOut.evals[0].trials[0].verdicts.isEmpty)
        #expect(timedOut.report.failed == 1)

        let failed = try await Runner(adapter: ThrowingAdapter(mode: .executionFailed), judge: ReplayJudge(["a": true]))
            .run(skill: ref, evals: evals, k: 1, injection: .ambient, base: base)
        #expect(failed.evals[0].trials[0].exit == .error, "the program running the model died, so nothing about the skill was measured")
    }

    @Test("An eval with no prompt records zero trials and FAILs, never crashing the run")
    func missingPromptFails() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let promptless = EvalCase(fields: ["id": .string("np"), "expectations": .array([.string("a")])])
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: ReplayJudge(["a": true]))
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [promptless], k: 3, injection: .ambient, base: base)
        #expect(outcome.evals[0].trials.isEmpty)
        #expect(outcome.report.failed == 1)
    }

    // MARK: - the real judge runner

    @Test("ClaudeCLIJudgeRunner shells the resolved binary with -p/--model and returns its stdout")
    func cliJudgeRunner() async throws {
        let launcher = FakeRunLauncher(output: ProcessOutput(stdout: "PASS: ok", stderr: "", exitCode: 0))
        let reply = try await ClaudeCLIJudgeRunner(binaryPath: "/usr/bin/claude", launcher: launcher)
            .ask(prompt: "grade this", model: "claude-sonnet-4-6")
        #expect(reply == "PASS: ok")
        #expect(await launcher.arguments.contains("-p"))
        #expect(await launcher.arguments.contains("grade this"))
        #expect(await launcher.arguments.contains("--model"))
        #expect(await launcher.arguments.contains("claude-sonnet-4-6"))
    }

    @Test("ClaudeCLIJudgeRunner throws JudgeRunnerError on a non-zero judge exit (infra, not a FAIL)")
    func cliJudgeRunnerThrowsOnFailure() async {
        let launcher = FakeRunLauncher(output: ProcessOutput(stdout: "", stderr: "auth error", exitCode: 1))
        await #expect(throws: JudgeRunnerError.self) {
            try await ClaudeCLIJudgeRunner(binaryPath: "/usr/bin/claude", launcher: launcher).ask(prompt: "x", model: "m")
        }
    }

    @Test("A judge subprocess failure marks the attempt ungraded, not a failure of the skill")
    func judgeFailureClassifiesFailed() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let failingRunner = ClaudeCLIJudgeRunner(binaryPath: "/x", launcher: FakeRunLauncher(output: ProcessOutput(stdout: "", stderr: "rate limit", exitCode: 1)))
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: TextJudge(runner: failingRunner, model: "m"))
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [evalCase("e", expectations: ["a"])], k: 1, injection: .ambient, base: base)
        #expect(outcome.evals[0].trials[0].exit == .error)        // ungraded, not a false criterion FAIL
        #expect(outcome.evals[0].trials[0].verdicts.isEmpty)
    }

    @Test("A hostile eval id cannot path-traverse the cache; records keep the real id")
    func hostileEvalIdConfinedToCache() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let hostile = EvalCase(fields: ["id": .string("../escape"), "prompt": .string("go"), "expectations": .array([.string("a")])])
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: ReplayJudge(["a": true]))
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [hostile], k: 1, injection: .ambient, base: base)
        #expect(outcome.evals[0].evalId == "../escape")   // real id preserved in records
        #expect(!FileManager.default.fileExists(atPath: base.deletingLastPathComponent().appendingPathComponent("escape").path))   // never escaped base
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("eval-0/trial-0/trace.json").path))             // wrote under base (index-based)
    }

    @Test("The runner gathers the post-run workspace listing and passes it into the judge")
    func runnerPassesListingToJudge() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let outcome = try await Runner(adapter: FileCreatingAdapter(filename: "report.md"), judge: EvidenceAssertingJudge(expectFile: "report.md"))
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [evalCase("e", expectations: ["produces report.md"])], k: 1, injection: .ambient, base: base)
        #expect(outcome.evals[0].trials[0].passed)   // judge saw report.md in the listing the runner gathered + passed
    }
}

/// **One walk, and it is the one that is bounded.**
///
/// Listing a finished workspace was written twice. One version counted entries and stopped at a limit;
/// the other read the whole folder in a single call and never looked at the limit — while its own
/// description claimed it did. The unbounded one was the version the grading path actually used, so a run
/// that produced tens of thousands of files could exhaust memory during the very step meant to record
/// what it produced.
///
/// **The test that was supposed to cover this called the wrong one of the two**, which is how the drift
/// survived. There is now one walk, so there is nothing left to drift.
@Suite("Listing a finished workspace stops at its limit")
struct WorkspaceWalkTests {
    private func workspace(files: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-walk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<files {
            try "x".write(to: root.appendingPathComponent("f\(i).txt"), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test("More entries than the limit are cut off, and the cut is reported")
    func stopsAtTheLimitAndSaysSo() throws {
        let root = try workspace(files: 12); defer { try? FileManager.default.removeItem(at: root) }
        let walked = WorkspaceManager.walk(root, cap: 5)
        #expect(walked.entries.count == 5, "it stops rather than reading everything into memory")
        #expect(walked.truncated, "and says it stopped, so a short list is not passed off as a whole one")
    }

    @Test("Fewer entries than the limit are all returned, and nothing is reported as cut")
    func underTheLimitIsComplete() throws {
        let root = try workspace(files: 3); defer { try? FileManager.default.removeItem(at: root) }
        let walked = WorkspaceManager.walk(root, cap: 5)
        #expect(walked.entries.count == 3)
        #expect(!walked.truncated)
    }

    /// **A shortcut is listed, not walked into.** The tree on the other side belongs to somebody else,
    /// and descending into one means walking whatever is there — possibly an enormous amount of it.
    @Test("A shortcut to a folder is listed without its contents")
    func shortcutNotDescended() throws {
        let root = try workspace(files: 1); defer { try? FileManager.default.removeItem(at: root) }
        let elsewhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-elsewhere-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        for i in 0..<4 {
            try "y".write(to: elsewhere.appendingPathComponent("hidden\(i).txt"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("shortcut"),
                                                   withDestinationURL: elsewhere)
        let walked = WorkspaceManager.walk(root, cap: 1000)
        #expect(walked.entries.contains("shortcut"), "the shortcut itself is listed")
        #expect(!walked.entries.contains { $0.contains("hidden") },
                "and nothing from the other side of it is: \(walked.entries)")
    }

    @Test("The limit used in real runs is far above any real one")
    func realLimitIsGenerous() {
        #expect(WorkspaceManager.producedEntryCap >= 10_000,
                "a real skill produces a handful of files; this only stops a runaway one")
    }
}


/// **A file list that was cut short must say so, and must never drop what the run produced.**
///
/// The grader is told this list answers whether a file exists, and it stops after a fixed number of
/// entries. It used to stop silently — the flag recording the cut was computed and thrown away by both
/// callers, while a comment claimed it was passed on. A run that installs dependencies or builds
/// something reaches the limit easily, and the file it actually produced could be pushed off the end, so
/// a check like "the run created report.md" would be marked failed with the file sitting right there.
/// That records a limitation of this tool as a fault in the skill being measured.
@Suite("A shortened file list reports the cut and keeps what the run produced")
struct ListingTruncationTests {
    private func makeSkill() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\n---\nbody".write(to: dir.appendingPathComponent("SKILL.md"),
                                               atomically: true, encoding: .utf8)
        return dir
    }

    private func workspace() throws -> (WorkspaceManager, Workspace, URL) {
        let skill = try makeSkill()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let wm = WorkspaceManager()
        let ws = try wm.prepare(skill: SkillRef(name: "demo", path: skill.path), files: [], base: base, label: "t0")
        for n in 0..<6 {
            try "x".write(to: ws.root.appendingPathComponent("f\(n).txt"), atomically: true, encoding: .utf8)
        }
        return (wm, ws, base)
    }

    @Test("A complete list says it is complete")
    func completeListSaysSo() throws {
        let (wm, ws, base) = try workspace(); defer { try? FileManager.default.removeItem(at: base) }
        let seen = wm.listing(ws)
        #expect(seen.truncated == false)
        #expect(seen.files.count >= 6)
    }

    /// The flag used to be computed here and discarded, so this is the whole point of the change.
    @Test("A list that hit the limit reports the cut")
    func cutListReportsIt() throws {
        let (wm, ws, base) = try workspace(); defer { try? FileManager.default.removeItem(at: base) }
        #expect(wm.listing(ws, cap: 2).truncated == true)
    }

    /// A produced file is present even when the walk stopped before reaching it — which is what stops a
    /// check about a file the run made from failing because the workspace was large.
    /// **A directory that cannot be read is reported as an incomplete list, not an empty one.**
    ///
    /// Answering "no files, and that is the whole list" tells the grader authoritatively that nothing
    /// exists, so every check of the form "the run created X" fails — a fault in this tool recorded as a
    /// fault in the skill. This matters more since the grader was taught to trust a list that does not
    /// say it was cut.
    @Test("An unreadable directory is an incomplete list, not an empty one")
    func unreadableDirectoryIsNotEmpty() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let (entries, truncated) = WorkspaceManager.walk(missing, cap: 10)
        #expect(entries.isEmpty)
        #expect(truncated == true, "an unreadable directory must not be reported as a complete empty list")
    }

    @Test("A produced file survives a cut that would otherwise have dropped it")
    func producedFileSurvivesTheCut() throws {
        let (wm, ws, base) = try workspace(); defer { try? FileManager.default.removeItem(at: base) }
        try "result".write(to: ws.root.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        // **A cut of nothing, because which file a cut of one reaches depends on the platform.** With a
        // limit of one the walk happened to reach `report.md` on Linux and not on macOS, so the guard that
        // makes this test mean anything passed on one and failed on the other. A limit of zero reaches
        // nothing anywhere, which is what the guard is actually trying to say.
        let cut = wm.listing(ws, cap: 0)
        #expect(cut.truncated == true)
        #expect(!cut.files.contains("report.md"), "the walk alone must not reach it — otherwise this proves nothing")
        let kept = wm.listing(ws, keeping: ["report.md"], cap: 0)
        #expect(kept.files.contains("report.md"), "a file the run produced must be listed however short the list is")
        #expect(kept.truncated == true, "keeping it does not make the rest of the list complete")
    }

    /// A shortcut pointing at something that is no longer there answers "no" to "does this exist", and
    /// leaves "is it a folder" untouched. Read only the second answer and it reads as a plain file; read
    /// only the first and the entry disappears from the list entirely. It has to stay listed: it is
    /// something the run left behind, and a list that quietly omits it is a list you cannot trust.
    @Test("A shortcut pointing at nothing stays in the list rather than vanishing from it")
    func brokenShortcutStaysListed() throws {
        let (wm, ws, base) = try workspace(); defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createSymbolicLink(
            at: ws.root.appendingPathComponent("dangling.txt"),
            withDestinationURL: ws.root.appendingPathComponent("never-written.txt"))
        let listed = wm.listing(ws).files
        #expect(listed.contains("dangling.txt"),
                "the walk found it, so dropping it here would report a workspace that is missing a file it actually has")
    }
}

/// **An attempt that was never graded is not a failure of the skill.**
///
/// When grading never happens — the grader errors, a rate limit hits, the connection drops, the program
/// running the model dies — the attempt used to be recorded as though the skill had been measured and
/// done badly. So a network problem lowered a skill's score, and on a before-and-after comparison it
/// could make a good edit look harmful. The code's own comment on that path said "the trial couldn't be
/// measured" while writing down the opposite.
///
/// The line drawn here is the one every major test runner uses and needs no judgement about causes: a
/// check that ran and came out negative is a failure; anything that stopped the check running is an
/// error. A run that exceeded its time limit stays a real result, because it does tell you something.
@Suite("An ungraded attempt is recorded as such, not as the skill failing")
struct UngradedAttemptTests {
    @Test("Attempts that never got graded are left out of the score instead of counted against it")
    func ungradedLeftOutOfTheScore() {
        let graded = TrialResult(exit: .passed, verdicts: [Verdict(criterion: "a", passed: true, rationale: "", judgeId: "t", model: "m", judgePromptVersion: "1")])
        let ungraded = TrialResult(exit: .error, verdicts: [])
        let record = EvalResult(evalId: "e", trials: [graded, graded, ungraded])

        #expect(record.recorded == 3, "all three attempts happened")
        #expect(record.errored == 1)
        #expect(record.measured == 2, "only two produced a result")
        #expect(record.passes == 2)
        // Counting the ungraded one against the skill would report two-thirds instead of everything.
        let report = try? RunReport(skill: "demo", results: [record])
        #expect(report?.passK == 1.0, "every attempt that was graded passed")
        #expect(report?.ungraded == 1, "and the loss is stated rather than hidden in a smaller rate")
    }

    @Test("A run where everything was graded reports no loss")
    func nothingLostReportsNothing() throws {
        let pass = TrialResult(exit: .passed, verdicts: [Verdict(criterion: "a", passed: true, rationale: "", judgeId: "t", model: "m", judgePromptVersion: "1")])
        let report = try RunReport(skill: "demo", results: [EvalResult(evalId: "e", trials: [pass, pass])])
        #expect(report.ungraded == 0)
        #expect(report.passK == 1.0)
    }

    /// A genuinely failing check must still count — this rule must not become a way for real failures to
    /// disappear, which would be the more damaging error of the two.
    @Test("A graded attempt that failed still counts against the skill")
    func realFailuresStillCount() throws {
        let fail = TrialResult(exit: .failed, verdicts: [Verdict(criterion: "a", passed: false, rationale: "", judgeId: "t", model: "m", judgePromptVersion: "1")])
        let report = try RunReport(skill: "demo", results: [EvalResult(evalId: "e", trials: [fail])])
        #expect(report.ungraded == 0, "it was graded; it just did not pass")
        #expect(report.passK == 0.0)
    }

    /// A run that exceeded its time limit did tell you something about the skill, so it is a result.
    @Test("Running out of time stays a real result, not an ungraded attempt")
    func timeoutIsStillAResult() throws {
        let out = TrialResult(exit: .timeout, verdicts: [])
        let record = EvalResult(evalId: "e", trials: [out])
        #expect(record.errored == 0)
        #expect(record.measured == 1, "a timeout counts; only never-graded attempts are dropped")
        #expect(try RunReport(skill: "demo", results: [record]).ungraded == 0)
    }
}

/// **A pipe, socket or device is not something to hand a model.**
///
/// Staging checked that a source was not a link and not a folder, then copied it — so anything else was
/// handed straight to the file-copying routine, and what happens then is decided by whichever
/// implementation of those routines the machine has. Measured on this one: copying a pipe fails
/// immediately with "operation not supported", a message that explains nothing to whoever sees it. That
/// is a guarantee borrowed from the platform rather than one this code makes, and this project builds for
/// more than one platform. The check that removes the borrowing already existed and was used by three
/// other readers here, each citing the same rule about opening a file whose kind you have not established.
@Suite("Only ordinary files are staged")
struct OrdinaryFilesOnlyTests {
    private func makePipe(in directory: URL, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pipe = directory.appendingPathComponent(name)
        #expect(mkfifo(pipe.path, 0o644) == 0, "the test needs a real pipe to be meaningful")
        return pipe
    }

    @Test("A named input that is a pipe is not accepted")
    func namedPipeIsRefused() throws {
        let skill = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: skill) }
        _ = try makePipe(in: skill.appendingPathComponent("fixtures"), named: "input.csv")
        #expect(WorkspaceManager.resolveFixture("fixtures/input.csv", skillDir: skill) == nil)
    }

    /// The contract this function actually has: it decides what is *permitted*, not what is present.
    @Test("A path that is simply not there is still permitted")
    func absentPathStillResolves() throws {
        let skill = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: skill) }
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        #expect(WorkspaceManager.resolveFixture("fixtures/missing.csv", skillDir: skill)?
            .sandboxRelativePath == "fixtures/missing.csv")
    }

    /// Inside a folder being staged, an odd entry is passed over rather than abandoning the run — the
    /// same treatment a link already gets there.
    @Test("A pipe found inside a staged folder is passed over, and the ordinary files still arrive")
    func pipeInsideAFolderIsSkipped() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("src")
        _ = try makePipe(in: source, named: "pipe")
        try "hello".write(to: source.appendingPathComponent("real.txt"), atomically: true, encoding: .utf8)

        let destination = root.appendingPathComponent("dst")
        try WorkspaceManager.copyFiltered(from: source, to: destination)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("real.txt").path),
                "the ordinary file must still be staged")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("pipe").path),
                "and the pipe must not be")
    }
}

/// **A run that could not even be set up says nothing about the skill.**
///
/// Before a skill is measured, it and its inputs are copied into a scratch folder. When that fails — a
/// missing input, a permission problem, a full disk — the attempt was recorded as *the skill was measured
/// and failed*, and the comment on that very line called it an infrastructure failure. So a setup problem
/// lowered the skill's score, and in a before-and-after comparison could make a working skill look broken.
/// The routing check had the same fault in two more places, and the test covering one of them asserted a
/// measured failure while its own name called the attempts infrastructure failures.
@Suite("A run that could not be set up is not a result about the skill")
struct SetupFailureIsNotAResultTests {
    private func makeSkill() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\n---\nbody".write(to: dir.appendingPathComponent("SKILL.md"),
                                               atomically: true, encoding: .utf8)
        return dir
    }

    @Test("An attempt whose inputs cannot be staged is recorded as never graded")
    func stagingFailureIsUngraded() async throws {
        let skill = try makeSkill()
        defer { try? FileManager.default.removeItem(at: skill) }
        // The scratch area is an ordinary file rather than a folder, so nothing can be prepared beneath
        // it — a stand-in for the real causes: no permission, a full disk, a broken layout.
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "not a folder".write(to: base, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: base) }

        let eval = EvalCase(fields: ["id": .string("e"), "prompt": .string("go"),
                                     "expectations": .array([.string("x")])])
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: ReplayJudge(["x": true]))
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [eval], k: 2,
                 injection: .ambient, base: base)

        let record = try #require(outcome.evals.first)
        #expect(record.trials.allSatisfy { $0.exit == .error }, "nothing about the skill was measured")
        #expect(record.measured == 0, "so nothing counts toward a score")
        #expect(record.errored == 2, "and both lost attempts are counted")
        #expect(outcome.report.ungraded == 2, "and reported rather than hidden in a lower score")
        // The row still *reads* "fail", which is the open item recorded in design §14-23 (the wording for
        // a check that graded nothing). What matters here is that nothing counts as measured, which is
        // what the exit decision and every score are built from — asserted above.
        #expect(outcome.report.evals.allSatisfy { $0.recorded == 0 },
                "no check has a graded attempt to draw a conclusion from")
    }
}

/// **How long an attempt took is measured on a clock that cannot go backwards.**
///
/// It used to be the difference between two readings of the wall clock — the one that says what time of
/// day it is, which gets adjusted by time-sync corrections, daylight-saving changes, and people setting it
/// by hand. An adjustment landing mid-measurement stretches, shrinks or reverses the answer, and this tool
/// publishes the difference in how long a run takes with a skill against without it, so a distorted
/// reading is a distorted result. A backwards adjustment could also record a duration below zero, which
/// nothing here refuses.
///
/// The clock cannot go backwards by construction, so there is nothing to test about that. What *is* worth
/// testing is the conversion into seconds written by hand beside it, where an exponent off by a few places
/// would report a run lasting milliseconds as one lasting hours, or the reverse.
@Suite("Elapsed time is measured on a clock that only counts forward")
struct ElapsedTimeTests {
    @Test("A known short interval converts to the right number of seconds")
    func shortIntervalConvertsCorrectly() async throws {
        let start = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(60))
        let measured = Runner.seconds(since: start)

        #expect(measured > 0, "time moved forward")
        // Generous either side of 60ms — this is checking the scale is right, not the scheduler's accuracy.
        #expect(measured > 0.03, "an exponent too small would report this as very nearly nothing: \(measured)")
        #expect(measured < 5.0, "an exponent too large would report a fraction of a second as minutes: \(measured)")
    }

    @Test("Sub-second precision survives; it is not rounded to whole seconds")
    func subSecondPrecisionSurvives() async throws {
        let start = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(40))
        let measured = Runner.seconds(since: start)
        // **The property is that fractions survive, not that the machine was quick.** Asserting the
        // measurement stayed under a second failed on a loaded build machine, where a forty-millisecond
        // wait took two seconds — the test was measuring how busy the machine was, which is not what it
        // is for. A value carrying a fraction is what "not rounded to whole seconds" actually means.
        #expect(measured != 0, "dropping the fractional part would make every quick attempt read as zero")
        #expect(measured != measured.rounded(), "a whole number would mean the fraction was discarded")
    }
}
