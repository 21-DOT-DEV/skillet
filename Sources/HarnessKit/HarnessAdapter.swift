import Foundation
import TraceKit

// MARK: - Supporting types
// Fully specified where F5 exercises them; minimal placeholders for the run/capture path that
// F6/F7 flesh out (the protocol signatures are stable; only these bodies grow).

/// A reference to a skill directory under test.
public struct SkillRef: Sendable, Equatable {
    public var name: String
    public var path: String
    public init(name: String, path: String) { self.name = name; self.path = path }
}

/// The A/B injection contract (§9.2): which skills are loadable vs. merely discoverable.
public enum SkillSet: Sendable {
    case none
    case only(load: [SkillRef], visible: [SkillRef] = [])
    case ambient
}

/// How an adapter materializes `.only` skills (§9.2). Adapters pick their own strategy.
public enum InjectionStrategy: Sendable {
    case discoveryPath
    case flag
    case inlineContext
}

/// The result of `probe()`: presence, version, and auth.
public struct HarnessInfo: Sendable, Equatable {
    public var id: HarnessID
    public var version: String
    public var authenticated: Bool
    public var available: Bool
    public init(id: HarnessID, version: String, authenticated: Bool, available: Bool) {
        self.id = id
        self.version = version
        self.authenticated = authenticated
        self.available = available
    }
}

/// One task to run through a harness. Minimal placeholder — fleshed out by F7 (`run`).
public struct TaskSpec: Sendable {
    public var query: String
    public var files: [String]
    public init(query: String, files: [String] = []) { self.query = query; self.files = files }
}

/// The per-trial sandbox a run executes in. Minimal placeholder — the real
/// create/stage/diff/destroy lifecycle is F7's.
public struct Workspace: Sendable {
    public var root: URL
    public init(root: URL) { self.root = root }
}

/// A harness's raw, un-normalized output (native session JSONL, API messages, …) before `parseTrace`.
public struct RawTrace: Sendable {
    public var harness: HarnessID
    public var raw: String
    public init(harness: HarnessID, raw: String) { self.harness = harness; self.raw = raw }
}

/// A reference to a native session in the harness's own store (capture side).
public struct NativeSessionRef: Sendable, Equatable {
    public var id: String
    public init(id: String) { self.id = id }
}

/// A query for locating native sessions to capture. Minimal placeholder.
public struct SessionQuery: Sendable {
    public var skill: String?
    public var last: Bool
    public init(skill: String? = nil, last: Bool = false) { self.skill = skill; self.last = last }
}

// MARK: - Errors

public enum HarnessError: Error, Sendable, Equatable {
    /// A declared capability whose implementation hasn't landed yet (e.g. claude-code in F5).
    case notImplemented(String)
    /// A capability the adapter does not have at all.
    case notSupported(capability: String)
}

// MARK: - The adapter seam (§9.1)

/// The one protocol every harness implements; the seam every later capability (capture, triage,
/// judging, `run`, the matrix) consumes. Defined in full now (D4) so later features build against a
/// stable contract; F5 ships only the `HarnessReplay` double + a claude-code stub.
public protocol HarnessAdapter: Sendable {
    var id: HarnessID { get }
    var capabilities: HarnessCapabilities { get }

    func probe() async throws -> HarnessInfo
    func verifySkillVisibility(_ skill: SkillRef, strategy: InjectionStrategy) throws
    func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace
    func parseTrace(_ raw: RawTrace) throws -> Trace
    func locateSessions(_ query: SessionQuery) async throws -> [NativeSessionRef]
    func exportSession(_ ref: NativeSessionRef) async throws -> RawTrace
}

/// Capability-gated methods degrade **loudly** by default (§9.1): an adapter that doesn't override
/// them is declaring it cannot do them, rather than silently no-opping. `probe()` has no default —
/// every adapter must answer "are you there?".
public extension HarnessAdapter {
    func verifySkillVisibility(_ skill: SkillRef, strategy: InjectionStrategy) throws {
        throw HarnessError.notSupported(capability: "skill_injection")
    }
    func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
        throw HarnessError.notSupported(capability: "run_task")
    }
    func parseTrace(_ raw: RawTrace) throws -> Trace {
        throw HarnessError.notSupported(capability: "trace_parsing")
    }
    func locateSessions(_ query: SessionQuery) async throws -> [NativeSessionRef] {
        throw HarnessError.notSupported(capability: "session_capture")
    }
    func exportSession(_ ref: NativeSessionRef) async throws -> RawTrace {
        throw HarnessError.notSupported(capability: "session_capture")
    }
}
