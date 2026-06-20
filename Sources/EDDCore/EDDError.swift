/// The one typed error hierarchy for skillet (design §11). Every case carries an ``ExitCode``, a
/// human `message` (what + why), and a `remedy` line (the fixing action) — Appendix B's
/// "errors: what/why/fix". `kind` is the machine-stable string surfaced in the `skillet.error/1`
/// payload, so scripts can branch on the error without parsing prose.
///
/// F1 defines only the cases reachable by the discovery/output substrate; later features extend it
/// (artifact, gate, measured-failure cases) without disturbing existing ones.
public enum EDDError: Error, Sendable, Equatable {
    /// A bad flag or argument. Exit ``ExitCode/usage``.
    case usage(message: String, remedy: String)
    /// `-C <dir>` pointed at a directory that does not exist or is not readable. Exit ``ExitCode/environment``.
    case directoryNotFound(path: String)
    /// A command that requires a project was run outside one. Exit ``ExitCode/environment``.
    /// (The mechanism lives in F1; project-requiring commands use it from F2 onward.)
    case projectNotFound(cwd: String)

    /// The stable exit code for this error.
    public var exitCode: ExitCode {
        switch self {
        case .usage: .usage
        case .directoryNotFound, .projectNotFound: .environment
        }
    }

    /// A machine-stable identifier for the error class (used in `skillet.error/1`).
    public var kind: String {
        switch self {
        case .usage: "usage"
        case .directoryNotFound: "directory_not_found"
        case .projectNotFound: "project_not_found"
        }
    }

    /// Human-readable "what went wrong, and why".
    public var message: String {
        switch self {
        case let .usage(message, _):
            message
        case let .directoryNotFound(path):
            "the directory passed to -C does not exist or is not readable: \(path)"
        case let .projectNotFound(cwd):
            "no skillet project found from \(cwd) (no skillet.yaml or .git boundary up the tree)"
        }
    }

    /// The exact next action that fixes the error.
    public var remedy: String {
        switch self {
        case let .usage(_, remedy):
            remedy
        case .directoryNotFound:
            "pass an existing, readable directory to -C, or omit -C to use the current directory"
        case .projectNotFound:
            "run from inside a skills repository, or initialize one with `skillet init`"
        }
    }
}
