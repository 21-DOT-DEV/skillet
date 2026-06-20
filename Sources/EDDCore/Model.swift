/// The current skillet version string. Reported by `--version` and in the `skillet.root/1` payload.
public enum SkilletVersion {
    public static let current = "0.0.0-dev"
}

/// How `skillet` located (or failed to locate) its project, git-style (design §5.1).
public enum DiscoveredVia: String, Codable, Sendable, Equatable {
    /// A `skillet.yaml` was found — the project root.
    case skilletYAML = "skillet_yaml"
    /// A `.git` boundary was found — the project root.
    case gitBoundary = "git_boundary"
    /// Neither marker was found walking up to the filesystem root.
    case none
}

/// The resolved project context for an invocation: where skillet thinks "the project" is, how it
/// decided, and where it started from. `root` is `nil` when no project was found (a benign state for
/// the root command, which works anywhere).
public struct ProjectContext: Codable, Sendable, Equatable {
    public let root: String?
    public let discoveredVia: DiscoveredVia
    public let cwd: String
    public let configPath: String?

    public init(root: String?, discoveredVia: DiscoveredVia, cwd: String, configPath: String?) {
        self.root = root
        self.discoveredVia = discoveredVia
        self.cwd = cwd
        self.configPath = configPath
    }
}

/// One verb of the EDD loop, for the command-less overview (design §6.3, Appendix B).
public struct LoopVerb: Codable, Sendable, Equatable {
    public let name: String
    public let summary: String
    public init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }

    /// The canonical loop, in spine order (design §6.1). Informational in F1 — the verbs are
    /// implemented across later phases.
    public static let canonical: [LoopVerb] = [
        .init(name: "init", summary: "adopt skillet in a repo"),
        .init(name: "lint", summary: "free static analysis of SKILL.md source"),
        .init(name: "run", summary: "measure: execute evals across harnesses"),
        .init(name: "capture", summary: "record a production session as evidence"),
        .init(name: "friction", summary: "log/inspect human-observed friction"),
        .init(name: "triage", summary: "mine the corpus into routed findings"),
        .init(name: "suggest", summary: "draft edit proposals from evidence"),
        .init(name: "next", summary: "the prioritized, gate-aware worklist"),
        .init(name: "iterate", summary: "A/B a proposal in a throwaway worktree"),
        .init(name: "report", summary: "render results for humans")
    ]
}

/// The `--json` payload for the root command: skillet's identity, the resolved project context, and
/// the loop overview.
public struct RootInfo: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.root/1"
    public let skilletVersion: String
    public let project: ProjectContext
    public let loop: [LoopVerb]

    public init(skilletVersion: String, project: ProjectContext, loop: [LoopVerb]) {
        self.skilletVersion = skilletVersion
        self.project = project
        self.loop = loop
    }
}

/// The `--json` payload for any error (emitted to stderr in `--json` mode). The exit code remains
/// the primary contract; this gives scripts a structured, prose-free handle on the failure.
public struct ErrorPayload: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.error/1"
    public let code: Int32
    public let kind: String
    public let message: String
    public let remedy: String

    public init(_ error: EDDError) {
        self.code = error.exitCode.rawValue
        self.kind = error.kind
        self.message = error.message
        self.remedy = error.remedy
    }
}
