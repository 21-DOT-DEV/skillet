/// The one typed error hierarchy for skillet (design §11). Every case carries an ``ExitCode``, a
/// human `message` (what + why), and a `remedy` line (the fixing action) — Appendix B's
/// "errors: what/why/fix". `kind` is the machine-stable string surfaced in the `skillet.error/1`
/// payload, so scripts can branch on the error without parsing prose.
public enum EDDError: Error, Sendable, Equatable {
    /// A bad flag or argument. Exit ``ExitCode/usage``.
    case usage(message: String, remedy: String)
    /// `-C <dir>` pointed at a directory that does not exist or is not readable. Exit ``ExitCode/environment``.
    case directoryNotFound(path: String)
    /// A command that requires a project was run outside one. Exit ``ExitCode/environment``.
    case projectNotFound(cwd: String)
    /// A harness binary could not be resolved (no flag/env/config/PATH). Exit ``ExitCode/environment``.
    case harnessNotFound(harness: String)
    /// An explicitly pinned harness binary is on the denylist. Exit ``ExitCode/environment``.
    case harnessBanned(harness: String, version: String)
    /// A skill is not visible to the harness under its injection strategy. Exit ``ExitCode/environment``.
    case skillNotVisible(skill: String, reason: String)

    /// The stable exit code for this error.
    public var exitCode: ExitCode {
        switch self {
        case .usage: .usage
        case .directoryNotFound, .projectNotFound, .harnessNotFound, .harnessBanned, .skillNotVisible: .environment
        }
    }

    /// A machine-stable identifier for the error class (used in `skillet.error/1`).
    public var kind: String {
        switch self {
        case .usage: "usage"
        case .directoryNotFound: "directory_not_found"
        case .projectNotFound: "project_not_found"
        case .harnessNotFound: "harness_not_found"
        case .harnessBanned: "harness_banned"
        case .skillNotVisible: "skill_not_visible"
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
        case let .harnessNotFound(harness):
            "could not find the \(harness) binary (checked the flag, env, config, and PATH)"
        case let .harnessBanned(harness, version):
            "the pinned \(harness) version \(version) is on the denylist (known-bad)"
        case let .skillNotVisible(skill, reason):
            "skill \(skill) is not visible to the harness: \(reason)"
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
        case let .harnessNotFound(harness):
            "install \(harness), or set its path via --harness-path, SKILLET_<ID>_BIN, or harness.<id>.path"
        case .harnessBanned:
            "pin a non-banned version, or set SKILLET_ALLOW_BANNED_<ID>=1 to override deliberately"
        case .skillNotVisible:
            "check the skill directory has a SKILL.md (and references/) resolvable under the harness"
        }
    }
}
