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
    private func makeSkill() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("references"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("evaluations"), withIntermediateDirectories: true)
        try "---\nname: demo\n---\nbody".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
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
        let listing = try wm.listing(ws)
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

    @Test("A harness timeout → .timeout trial; a non-zero exit → .failed trial; both fail the eval")
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
        #expect(failed.evals[0].trials[0].exit == .failed)
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

    @Test("A judge subprocess failure marks the trial failed/ungraded, not a criterion FAIL")
    func judgeFailureClassifiesFailed() async throws {
        let skill = try makeSkill(); defer { try? FileManager.default.removeItem(at: skill) }
        let base = tempDir(); defer { try? FileManager.default.removeItem(at: base) }
        let failingRunner = ClaudeCLIJudgeRunner(binaryPath: "/x", launcher: FakeRunLauncher(output: ProcessOutput(stdout: "", stderr: "rate limit", exitCode: 1)))
        let outcome = try await Runner(adapter: ReplayAdapter(), judge: TextJudge(runner: failingRunner, model: "m"))
            .run(skill: SkillRef(name: "demo", path: skill.path), evals: [evalCase("e", expectations: ["a"])], k: 1, injection: .ambient, base: base)
        #expect(outcome.evals[0].trials[0].exit == .failed)        // ungraded, not a false criterion FAIL
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
