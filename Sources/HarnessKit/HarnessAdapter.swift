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

/// The result of `probe()`: presence, version, auth, and any non-fatal warnings (e.g. an
/// auto-discovered binary on the denylist — surfaced loudly, but not refused; §9.1). The optional
/// resolution fields (`binaryPath`, `source`, `bannedVersion`) are additive for `doctor` (F3):
/// adapters that resolve a real binary fill them so the preflight can report the winning link and
/// classify a banned auto-discovered version without string-sniffing `warnings`.
public struct HarnessInfo: Sendable, Equatable {
    public var id: HarnessID
    public var version: String
    public var authenticated: Bool
    public var available: Bool
    public var warnings: [String]
    /// The resolved binary path (when the adapter shells a real binary).
    public var binaryPath: String?
    /// The winning resolution link (`flag`/`env`/`config`/`path`, §9.1) that produced `binaryPath`.
    public var source: String?
    /// Set when the resolved version is denylisted but non-strict probing continued (auto-discovered).
    public var bannedVersion: String?
    public init(
        id: HarnessID,
        version: String,
        authenticated: Bool,
        available: Bool,
        warnings: [String] = [],
        binaryPath: String? = nil,
        source: String? = nil,
        bannedVersion: String? = nil
    ) {
        self.id = id
        self.version = version
        self.authenticated = authenticated
        self.available = available
        self.warnings = warnings
        self.binaryPath = binaryPath
        self.source = source
        self.bannedVersion = bannedVersion
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

/// A reference to a native session in the harness's own store (capture side). `id` is the session's
/// native identifier (its filename stem); `path` is the absolute file `exportSession` reads.
public struct NativeSessionRef: Sendable, Equatable {
    public var id: String
    public var path: String
    public init(id: String, path: String = "") { self.id = id; self.path = path }
}

/// A query for locating native sessions to capture. `workspace` is the directory the session ran in
/// (`--target-dir`, default cwd) — claude-code keys its store by that path, so newest-session resolution
/// must use it, not the cwd where `skillet` was launched (R4-3).
public struct SessionQuery: Sendable {
    public var skill: String?
    public var workspace: URL?
    public init(skill: String? = nil, workspace: URL? = nil) {
        self.skill = skill
        self.workspace = workspace
    }
}

// MARK: - Errors

public enum HarnessError: Error, Sendable, Equatable {
    /// A declared capability whose implementation hasn't landed yet (e.g. claude-code in F5).
    case notImplemented(String)
    /// A capability the adapter does not have at all.
    case notSupported(capability: String)
    /// The harness ran but exited non-zero — the trial could not be executed (the run loop classifies
    /// this distinctly from a judged failure, design §10).
    case executionFailed(harness: String, exitCode: Int32, stderr: String)
}

// MARK: - The adapter seam (§9.1)

/// The one protocol every harness implements; the seam every later capability (capture, triage,
/// judging, `run`, the matrix) consumes. Defined in full now (D4) so later features build against a
/// stable contract; F5 ships only the `ReplayAdapter` double + a claude-code stub.
public protocol HarnessAdapter: Sendable {
    var id: HarnessID { get }
    var capabilities: HarnessCapabilities { get }

    /// Resolve + vet the harness. `strict` is the spend-gating preflight (`run`): an auto-discovered
    /// banned binary or an unauthenticated harness throws (exit 3) instead of merely warning, so a paid
    /// run never starts on a known-bad or logged-out harness. Non-strict (`harness info`) reports the
    /// same conditions as `warnings`/`authenticated: false` without throwing.
    func probe(strict: Bool) async throws -> HarnessInfo
    func verifySkillVisibility(_ skill: SkillRef, strategy: InjectionStrategy) throws
    func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace
    func parseTrace(_ raw: RawTrace) throws -> Trace
    func locateSessions(_ query: SessionQuery) async throws -> [NativeSessionRef]
    func exportSession(_ ref: NativeSessionRef) async throws -> RawTrace
    /// Prove the harness can run a `SkillSet.none` baseline arm with ambient skills provably
    /// excluded (F15, §9.2) — a **$0** check, run before any paid `--ab` trial. Throws (never
    /// warns) when isolation can't be proven: `--ab` is refused rather than polluted.
    func verifyBaselineIsolation() async throws
}

/// Capability-gated methods degrade **loudly** by default (§9.1): an adapter that doesn't override
/// them is declaring it cannot do them, rather than silently no-opping. `probe(strict:)` has no default
/// — every adapter must answer "are you there?"; the `probe()` convenience is the non-strict form.
public extension HarnessAdapter {
    /// The informational probe (`harness info`): warn-not-fail, never throws on banned/unauthenticated.
    func probe() async throws -> HarnessInfo { try await probe(strict: false) }

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
    func verifyBaselineIsolation() async throws {
        throw HarnessError.notSupported(capability: "baseline_isolation")
    }
}
