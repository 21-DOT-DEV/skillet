import Testing
import Foundation
import EDDCore
import TraceKit
import HarnessKit
import JudgeKit
@testable import RunKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("RunKit — grounded content capture (F16)")
struct GroundedCaptureRunKitTests {
    private let fm = FileManager.default
    private func tempWorkspace() throws -> Workspace {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return Workspace(root: root)
    }
    private func write(_ ws: Workspace, _ rel: String, _ text: String) throws {
        let url = ws.root.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    private func find(_ files: [FileContent], _ path: String) -> FileContent? { files.first { $0.path == path } }

    @Test("The snapshot diff: created + modified captured, untouched skipped, deleted disclosed")
    func producedSet() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        try write(ws, "keep.txt", "keep")     // staged, will stay untouched
        try write(ws, "edit.txt", "v1")       // staged, will be modified
        try write(ws, "del.txt", "x")         // staged, will be deleted
        let baseline = wm.snapshotStaged(ws)
        #expect(baseline.count == 3)

        try write(ws, "out.txt", "hello")     // produced (created)
        try write(ws, "edit.txt", "v2")       // modified in place
        try fm.removeItem(at: ws.root.appendingPathComponent("del.txt"))

        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 1 << 20)
        #expect(find(produced, "out.txt")?.change == .created)
        #expect(find(produced, "out.txt")?.content == "hello")
        #expect(find(produced, "edit.txt")?.change == .modified)
        #expect(find(produced, "edit.txt")?.content == "v2")
        #expect(find(produced, "del.txt")?.change == .deleted)
        #expect(find(produced, "del.txt")?.content == nil)
        #expect(find(produced, "keep.txt") == nil)   // untouched input never graded as output
    }

    @Test("Per-file cut: a file over the per-file cap is a disclosed prefix")
    func perFileCut() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        let baseline = wm.snapshotStaged(ws)
        try write(ws, "big.txt", String(repeating: "a", count: 100))
        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 40, totalCap: 1 << 20)
        let big = find(produced, "big.txt")
        #expect(big?.content?.count == 40)
        #expect(big?.truncatedBytes == 60)
    }

    @Test("Total cap: touched-first budget fills, then later files are disclosed as omitted")
    func totalCap() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        let baseline = wm.snapshotStaged(ws)
        try write(ws, "a.txt", String(repeating: "x", count: 100))
        try write(ws, "b.txt", String(repeating: "y", count: 100))
        // total budget only fits the first (path-sorted) file.
        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 100)
        #expect(find(produced, "a.txt")?.content?.count == 100)
        #expect(find(produced, "b.txt")?.content == nil)          // budget spent
        #expect(find(produced, "b.txt")?.omitted == true)         // disclosed as omitted (no prefix), not truncation
        #expect(find(produced, "b.txt")?.truncatedBytes == 0)     // truncatedBytes strictly pairs with a shown prefix
        #expect(find(produced, "b.txt")?.sizeBytes == 100)        // size still disclosed
    }

    @Test("A non-text (NUL-containing) file has its contents withheld and disclosed as binary + size")
    func binaryElided() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        let baseline = wm.snapshotStaged(ws)
        try Data([0x89, 0x50, 0x00, 0x4E, 0x47]).write(to: ws.root.appendingPathComponent("img.png"))
        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 1 << 20)
        #expect(find(produced, "img.png")?.binary == true)
        #expect(find(produced, "img.png")?.content == nil)
        #expect(find(produced, "img.png")?.sizeBytes == 5)   // finding 3: withheld size disclosed
    }

    @Test("finding 2: non-UTF-8 bytes WITHOUT a NUL are withheld as binary, never lossy-decoded to U+FFFD")
    func nonUTF8NoNulElided() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        let baseline = wm.snapshotStaged(ws)
        try Data([0xFF, 0xFE, 0xFF]).write(to: ws.root.appendingPathComponent("blob"))   // invalid UTF-8, no NUL
        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 1 << 20)
        #expect(find(produced, "blob")?.binary == true)
        #expect(find(produced, "blob")?.content == nil)   // NOT "\u{FFFD}\u{FFFD}\u{FFFD}"
        #expect(find(produced, "blob")?.sizeBytes == 3)
    }

    @Test("finding: valid UTF-8 then an invalid byte (0xFF) at the cap boundary is binary, NOT stripped to text")
    func invalidByteAtCapIsBinary() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        let baseline = wm.snapshotStaged(ws)
        // First `cap` bytes = 7 ASCII + a lone 0xFF (never a valid UTF-8 byte); more bytes follow so
        // the read is truncated. The old lead-byte trim stripped 0xFF and called the prefix "text".
        var bytes = Data(repeating: 0x61, count: 7)   // "aaaaaaa"
        bytes.append(0xFF)
        bytes.append(contentsOf: Data(repeating: 0x61, count: 10))   // tail → fullSize > cap → truncated
        try bytes.write(to: ws.root.appendingPathComponent("blob.bin"))
        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 8, totalCap: 1 << 20)
        #expect(find(produced, "blob.bin")?.binary == true)
        #expect(find(produced, "blob.bin")?.content == nil)   // 0xFF is not a truncation artifact
    }

    @Test("finding 2: a UTF-8 character cut at the byte cap stays clean text (trimmed), never mangled")
    func truncatedScalarStaysText() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        let baseline = wm.snapshotStaged(ws)
        try "aé".write(to: ws.root.appendingPathComponent("t.txt"), atomically: true, encoding: .utf8)  // a=1 byte, é=2 bytes
        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 2, totalCap: 1 << 20)   // cap splits é
        let t = find(produced, "t.txt")
        #expect(t?.content == "a")                 // the partial 'é' is trimmed, not turned into U+FFFD
        #expect(t?.content?.contains("\u{FFFD}") == false)
        #expect(t?.truncatedBytes == 2)            // 3 full − 1 shown
    }

    @Test("finding 1 SECURITY/DoS: a FIFO output is disclosed without being opened — capture never hangs", .timeLimit(.minutes(1)))
    func fifoNeverOpened() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        let baseline = wm.snapshotStaged(ws)
        let fifo = ws.root.appendingPathComponent("pipe")
        #expect(mkfifo(fifo.path, 0o644) == 0)   // the skill mkfifo's in the sandbox
        // With no writer, opening this pipe blocks forever — capture must NOT open it (the .timeLimit
        // turns a regression back into a failure, not a hung suite).
        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 1 << 20)
        #expect(find(produced, "pipe")?.special == true)
        #expect(find(produced, "pipe")?.content == nil)
    }

    @Test("finding 4: a staged file replaced by a dangling symlink is recorded once (modified symlink), not also deleted")
    func danglingSymlinkNotDoubleRecorded() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        try write(ws, "f.txt", "orig")
        let baseline = wm.snapshotStaged(ws)
        try fm.removeItem(at: ws.root.appendingPathComponent("f.txt"))
        try fm.createSymbolicLink(at: ws.root.appendingPathComponent("f.txt"), withDestinationURL: URL(fileURLWithPath: "/no/such/target"))
        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 1 << 20)
        let entries = produced.filter { $0.path == "f.txt" }
        #expect(entries.count == 1)                    // not double-recorded as modified + deleted
        #expect(entries.first?.symlink == true)
        #expect(entries.first?.change == .modified)
    }

    @Test("P1 SECURITY: a symlinked output is never followed — no host contents leak into the evidence")
    func symlinkNeverFollowed() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        // A host secret OUTSIDE the workspace.
        let secretDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: secretDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: secretDir) }
        let secret = secretDir.appendingPathComponent("passwd")
        try "TOP-SECRET-HOST-BYTES".write(to: secret, atomically: true, encoding: .utf8)
        let baseline = wm.snapshotStaged(ws)
        // The skill "writes" out.txt as a symlink to the host secret.
        try fm.createSymbolicLink(at: ws.root.appendingPathComponent("out.txt"), withDestinationURL: secret)

        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 1 << 20)
        #expect(find(produced, "out.txt")?.symlink == true)
        #expect(find(produced, "out.txt")?.content == nil)         // never read
        #expect(!produced.contains { $0.content?.contains("SECRET") == true })   // no host bytes anywhere
    }

    @Test("A hard link to a host file is disclosed (link count > 1) and never read — no content leak")
    func hardLinkNeverRead() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        // A host secret OUTSIDE the workspace, on the same filesystem (both under the temp dir).
        let secret = fm.temporaryDirectory.appendingPathComponent("secret-\(UUID().uuidString)")
        try "TOP-SECRET-HARDLINK-BYTES".write(to: secret, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: secret) }
        let baseline = wm.snapshotStaged(ws)
        // The skill "produces" out.txt as a HARD link to the host secret (not a symlink).
        let dest = ws.root.appendingPathComponent("out.txt")
        guard link(secret.path, dest.path) == 0 else {
            // Same-fs hard link should succeed under the temp dir; if the platform blocks it, the escape
            // is impossible anyway — nothing to assert.
            return
        }
        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 1 << 20)
        #expect(find(produced, "out.txt")?.hardlink == true)
        #expect(find(produced, "out.txt")?.content == nil)                       // never read
        #expect(!produced.contains { $0.content?.contains("SECRET") == true })   // no host bytes anywhere
    }

    @Test("A symlinked directory is disclosed as a symlink and never descended (no child path, no leak)")
    func symlinkedDirNotDescended() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        let secretDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: secretDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: secretDir) }
        try "SECRET-IN-TREE".write(to: secretDir.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        let baseline = wm.snapshotStaged(ws)
        try fm.createSymbolicLink(at: ws.root.appendingPathComponent("linkdir"), withDestinationURL: secretDir)

        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 1 << 20)
        #expect(find(produced, "linkdir")?.symlink == true)                      // the link itself is disclosed
        #expect(!produced.contains { $0.path.hasPrefix("linkdir/") })            // no phantom child path enters evidence
        #expect(!produced.contains { $0.content?.contains("SECRET") == true })   // and no host bytes leak
    }

    @Test("A regular file that can't be opened (chmod 000) is disclosed as unreadable, never silently dropped")
    func unreadableFileDisclosed() throws {
        let wm = WorkspaceManager()
        let ws = try tempWorkspace(); defer { try? wm.destroy(ws) }
        let baseline = wm.snapshotStaged(ws)
        let locked = ws.root.appendingPathComponent("locked.txt")
        try "cannot read me".write(to: locked, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }   // so teardown can remove it

        let produced = wm.readProducedContents(ws, baseline: baseline, perFileCap: 1 << 16, totalCap: 1 << 20)
        let entry = find(produced, "locked.txt")
        #expect(entry != nil)                       // disclosed, not dropped
        #expect(entry?.unreadable == true)
        #expect(entry?.content == nil)
        #expect(entry?.sizeBytes == 14)             // size still disclosed from metadata
    }

    @Test("Grounded evidence is persisted to the run cache (file_contents.json) for replay/re-grade")
    func evidencePersisted() async throws {
        let skill = try makeSkill(); defer { try? fm.removeItem(at: skill) }
        let ref = SkillRef(name: "demo", path: skill.path)
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? fm.removeItem(at: base) }
        _ = try await Runner(adapter: FileWritingAdapter(), judge: EvidenceCapturingJudge(box: .init()), evidencePolicy: .groundedDefault)
            .run(skill: ref, evals: [evalCase("e")], k: 1, injection: .only(load: [ref]), base: base, keepWorkspace: false)
        let evidenceFile = base.appendingPathComponent("eval-0/trial-0/file_contents.json")
        #expect(fm.fileExists(atPath: evidenceFile.path))   // survives workspace teardown
        let decoded = try JSONDecoder().decode([FileContent].self, from: Data(contentsOf: evidenceFile))
        #expect(decoded.contains { $0.path == "out.txt" && $0.content == "produced!" })
    }

    @Test("The text (listing-only) policy writes no file_contents.json (no capture, no cost)")
    func noEvidenceFileUnderTextPolicy() async throws {
        let skill = try makeSkill(); defer { try? fm.removeItem(at: skill) }
        let ref = SkillRef(name: "demo", path: skill.path)
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? fm.removeItem(at: base) }
        _ = try await Runner(adapter: FileWritingAdapter(), judge: EvidenceCapturingJudge(box: .init()), evidencePolicy: .listingOnly)
            .run(skill: ref, evals: [evalCase("e")], k: 1, injection: .only(load: [ref]), base: base)
        #expect(!fm.fileExists(atPath: base.appendingPathComponent("eval-0/trial-0/file_contents.json").path))
    }

    /// Runs, writes nothing — for the empty-produced-set case (a "wrote X" failure is itself evidence).
    struct NoOpAdapter: HarnessAdapter {
        let id: HarnessID = "noop"
        let capabilities: HarnessCapabilities = [.runTask, .traceParsing]
        func probe(strict: Bool) async throws -> HarnessInfo { HarnessInfo(id: id, version: "x", authenticated: true, available: true) }
        func parseTrace(_ raw: RawTrace) throws -> Trace { ReplayAdapter.cannedTrace }
        func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace { RawTrace(harness: id, raw: "noop") }
    }
    /// Writes out.txt during run, then fails to parse — exercises the catch-path capture.
    struct ParseFailingAdapter: HarnessAdapter {
        struct ParseBoom: Error {}
        let id: HarnessID = "parsefail"
        let capabilities: HarnessCapabilities = [.runTask, .traceParsing]
        func probe(strict: Bool) async throws -> HarnessInfo { HarnessInfo(id: id, version: "x", authenticated: true, available: true) }
        func parseTrace(_ raw: RawTrace) throws -> Trace { throw ParseBoom() }
        func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
            try "produced!".write(to: workspace.root.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
            return RawTrace(harness: id, raw: "wrote out.txt")
        }
    }
    /// Fires a skill (pollution) AND writes a file — exercises capture on the polluted return.
    struct PollutingFileAdapter: HarnessAdapter {
        let id: HarnessID = "pollutefile"
        let capabilities: HarnessCapabilities = [.runTask, .traceParsing, .baselineIsolation]
        func probe(strict: Bool) async throws -> HarnessInfo { HarnessInfo(id: id, version: "x", authenticated: true, available: true) }
        func parseTrace(_ raw: RawTrace) throws -> Trace { ReplayAdapter.cannedTrace }   // fires "demo" → pollution
        func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
            try "leaked".write(to: workspace.root.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
            return RawTrace(harness: id, raw: "x")
        }
        func verifyBaselineIsolation() async throws {}
    }

    @Test("finding: an EMPTY produced set under grounded still persists file_contents.json ([]), distinct from not-captured")
    func emptyProducedSetPersisted() async throws {
        let skill = try makeSkill(); defer { try? fm.removeItem(at: skill) }
        let ref = SkillRef(name: "demo", path: skill.path)
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? fm.removeItem(at: base) }
        _ = try await Runner(adapter: NoOpAdapter(), judge: ReplayJudge(["a": true]), evidencePolicy: .groundedDefault)
            .run(skill: ref, evals: [evalCase("e")], k: 1, injection: .only(load: [ref]), base: base)
        let f = base.appendingPathComponent("eval-0/trial-0/file_contents.json")
        #expect(fm.fileExists(atPath: f.path))
        #expect(try JSONDecoder().decode([FileContent].self, from: Data(contentsOf: f)).isEmpty)
    }

    @Test("finding: a parse-FAILURE trial under grounded still persists the produced evidence (catch-path capture)")
    func parseFailurePersistsEvidence() async throws {
        let skill = try makeSkill(); defer { try? fm.removeItem(at: skill) }
        let ref = SkillRef(name: "demo", path: skill.path)
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? fm.removeItem(at: base) }
        let outcome = try await Runner(adapter: ParseFailingAdapter(), judge: ReplayJudge(["a": true]), evidencePolicy: .groundedDefault)
            .run(skill: ref, evals: [evalCase("e")], k: 1, injection: .only(load: [ref]), base: base)
        #expect(outcome.evals[0].trials[0].exit == .failed)   // parse threw
        let f = base.appendingPathComponent("eval-0/trial-0/file_contents.json")
        #expect(fm.fileExists(atPath: f.path))
        let decoded = try JSONDecoder().decode([FileContent].self, from: Data(contentsOf: f))
        #expect(decoded.contains { $0.path == "out.txt" && $0.content == "produced!" })   // evidence survived the failure
    }

    /// Writes a file, then throws a timeout — exercises the ProcessError catch-path capture.
    struct TimeoutWritingAdapter: HarnessAdapter {
        let id: HarnessID = "timeoutwrite"
        let capabilities: HarnessCapabilities = [.runTask, .traceParsing]
        func probe(strict: Bool) async throws -> HarnessInfo { HarnessInfo(id: id, version: "x", authenticated: true, available: true) }
        func parseTrace(_ raw: RawTrace) throws -> Trace { ReplayAdapter.cannedTrace }
        func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
            try "partial output".write(to: workspace.root.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
            throw ProcessError.timedOut(after: .seconds(1))
        }
    }

    @Test("finding: a TIMEOUT/process-failure trial under grounded persists produced evidence (ProcessError catch path)")
    func timeoutPersistsEvidence() async throws {
        let skill = try makeSkill(); defer { try? fm.removeItem(at: skill) }
        let ref = SkillRef(name: "demo", path: skill.path)
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? fm.removeItem(at: base) }
        let outcome = try await Runner(adapter: TimeoutWritingAdapter(), judge: ReplayJudge(["a": true]), evidencePolicy: .groundedDefault)
            .run(skill: ref, evals: [evalCase("e")], k: 1, injection: .only(load: [ref]), base: base)
        #expect(outcome.evals[0].trials[0].exit == .timeout)
        let f = base.appendingPathComponent("eval-0/trial-0/file_contents.json")
        #expect(fm.fileExists(atPath: f.path))   // the ProcessError catch captured from the live workspace
        #expect(try JSONDecoder().decode([FileContent].self, from: Data(contentsOf: f)).contains { $0.path == "out.txt" })
    }

    @Test("finding: a POLLUTED baseline trial under grounded still persists its produced evidence")
    func pollutedTrialPersistsEvidence() async throws {
        let skill = try makeSkill(); defer { try? fm.removeItem(at: skill) }
        let ref = SkillRef(name: "demo", path: skill.path)
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? fm.removeItem(at: base) }
        let results = await Runner(adapter: PollutingFileAdapter(), judge: ReplayJudge(["a": true]), evidencePolicy: .groundedDefault)
            .runBaseline(skill: ref, evals: [evalCase("e")], k: 1, base: base)
        #expect(results[0].polluted == 1)
        let f = base.appendingPathComponent("baseline/eval-0/trial-0/file_contents.json")
        #expect(fm.fileExists(atPath: f.path))
        #expect(try JSONDecoder().decode([FileContent].self, from: Data(contentsOf: f)).contains { $0.path == "out.txt" })
    }

    // MARK: - Runner policy gating

    /// Records whether the runner handed the judge any produced-file contents.
    struct EvidenceCapturingJudge: Judge {
        final class Box: @unchecked Sendable { var fileContents: [FileContent]? = nil; var seen = false }
        let box: Box
        func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict {
            box.seen = true
            box.fileContents = evidence.fileContents
            return Verdict(criterion: criterion, passed: true, rationale: "r", judgeId: "x", model: "m", judgePromptVersion: "v")
        }
    }
    /// Writes a file during the run so the produced-set is non-empty.
    struct FileWritingAdapter: HarnessAdapter {
        let id: HarnessID = "filewriter"
        let capabilities: HarnessCapabilities = [.runTask, .traceParsing]
        func probe(strict: Bool) async throws -> HarnessInfo { HarnessInfo(id: id, version: "x", authenticated: true, available: true) }
        func parseTrace(_ raw: RawTrace) throws -> Trace { ReplayAdapter.cannedTrace }
        func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
            try "produced!".write(to: workspace.root.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
            return RawTrace(harness: id, raw: "wrote out.txt")
        }
    }
    private func makeSkill() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\n---\nb".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return dir
    }
    private func evalCase(_ id: String) -> EvalCase {
        EvalCase(fields: ["id": .string(id), "prompt": .string("go"), "expectations": .array([.string("a")])])
    }

    @Test("Runner: the grounded policy hands produced contents to the judge; listing-only hands nil (no read)")
    func policyGating() async throws {
        let skill = try makeSkill(); defer { try? fm.removeItem(at: skill) }
        let ref = SkillRef(name: "demo", path: skill.path)

        let withBox = EvidenceCapturingJudge.Box()
        let base1 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? fm.removeItem(at: base1) }
        _ = try await Runner(adapter: FileWritingAdapter(), judge: EvidenceCapturingJudge(box: withBox), evidencePolicy: .groundedDefault)
            .run(skill: ref, evals: [evalCase("e")], k: 1, injection: .only(load: [ref]), base: base1)
        #expect(withBox.fileContents != nil)
        #expect(withBox.fileContents?.contains { $0.path == "out.txt" && $0.content == "produced!" } == true)

        let plainBox = EvidenceCapturingJudge.Box()
        let base2 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? fm.removeItem(at: base2) }
        _ = try await Runner(adapter: FileWritingAdapter(), judge: EvidenceCapturingJudge(box: plainBox), evidencePolicy: .listingOnly)
            .run(skill: ref, evals: [evalCase("e")], k: 1, injection: .only(load: [ref]), base: base2)
        #expect(plainBox.seen)
        #expect(plainBox.fileContents == nil)   // text path: never captured, no cost
    }
}
