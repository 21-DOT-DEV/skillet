/// The one typed error hierarchy for skillet (design §11). Every case carries an ``ExitCode``, a
/// human `message` (what + why), and a `remedy` line (the fixing action) — Appendix B's
/// "errors: what/why/fix". `kind` is the machine-stable string surfaced in the `skillet.error/1`
/// payload, so scripts can branch on the error without parsing prose.
public enum EDDError: Error, Sendable, Equatable {
    /// A bad flag or argument. Exit ``ExitCode/usage``.
    case usage(message: String, remedy: String)
    /// `-C <dir>` pointed at a directory that does not exist or is not readable. Exit ``ExitCode/environment``.
    case directoryNotFound(path: String)
    /// A command argument that must name an existing file or directory did not (e.g. `skillet score <path>`).
    /// Exit ``ExitCode/environment``.
    case pathNotFound(path: String)
    /// A command that requires a project was run outside one. Exit ``ExitCode/environment``.
    case projectNotFound(cwd: String)
    /// A harness binary could not be resolved (no flag/env/config/PATH). Exit ``ExitCode/environment``.
    case harnessNotFound(harness: String)
    /// An explicitly pinned harness binary is on the denylist. Exit ``ExitCode/environment``.
    case harnessBanned(harness: String, version: String)
    /// The harness resolved + ran but is not authenticated (e.g. `claude auth status` reports logged-out).
    /// Exit ``ExitCode/environment`` — caught at preflight, before any paid trial.
    case harnessUnauthenticated(harness: String)
    /// A skill is not visible to the harness under its injection strategy. Exit ``ExitCode/environment``.
    case skillNotVisible(skill: String, reason: String)
    /// The harness cannot prove a skill-free baseline arm (`--ab`, §9.2: isolate ambient skills or
    /// declare it cannot) — refused before spend, never a polluted baseline. Exit ``ExitCode/environment``.
    case baselineNotIsolable(harness: String, reason: String)
    /// A committed artifact is corrupt/invalid against its schema (e.g. unparseable `evals.json`).
    /// Exit ``ExitCode/artifact``.
    case invalidArtifact(path: String, reason: String)
    /// The secret scanner (`betterleaks`) could not be resolved or run, so `capture` cannot prove the
    /// bundle was scrubbed — it fails closed rather than write an unsanitized bundle (constitution VI).
    /// Exit ``ExitCode/environment``.
    case sanitizerNotFound(reason: String)
    /// One or more `capture` bundle files already exist and `--force` was not given. Exit ``ExitCode/environment``.
    case captureDestinationExists(paths: [String])
    /// `capture` found no native session for the workspace. Exit ``ExitCode/environment``.
    case sessionNotFound(workspace: String)

    /// The stable exit code for this error.
    public var exitCode: ExitCode {
        switch self {
        case .usage: .usage
        case .directoryNotFound, .pathNotFound, .projectNotFound, .harnessNotFound, .harnessBanned, .harnessUnauthenticated, .skillNotVisible, .baselineNotIsolable, .sanitizerNotFound, .captureDestinationExists, .sessionNotFound: .environment
        case .invalidArtifact: .artifact
        }
    }

    /// A machine-stable identifier for the error class (used in `skillet.error/1`).
    public var kind: String {
        switch self {
        case .usage: "usage"
        case .directoryNotFound: "directory_not_found"
        case .pathNotFound: "path_not_found"
        case .projectNotFound: "project_not_found"
        case .harnessNotFound: "harness_not_found"
        case .harnessBanned: "harness_banned"
        case .harnessUnauthenticated: "harness_unauthenticated"
        case .skillNotVisible: "skill_not_visible"
        case .baselineNotIsolable: "baseline_not_isolable"
        case .invalidArtifact: "invalid_artifact"
        case .sanitizerNotFound: "sanitizer_not_found"
        case .captureDestinationExists: "capture_destination_exists"
        case .sessionNotFound: "session_not_found"
        }
    }

    /// Human-readable "what went wrong, and why".
    public var message: String {
        switch self {
        case let .usage(message, _):
            message
        case let .directoryNotFound(path):
            "the directory passed to -C does not exist or is not readable: \(path)"
        case let .pathNotFound(path):
            "the path to score does not exist or is not readable: \(path)"
        case let .projectNotFound(cwd):
            "no skillet project found from \(cwd) (no skillet.yaml or .git boundary up the tree)"
        case let .harnessNotFound(harness):
            "could not find the \(harness) binary (checked the flag, env, config, and PATH)"
        case let .harnessBanned(harness, version):
            "the pinned \(harness) version \(version) is on the denylist (known-bad)"
        case let .harnessUnauthenticated(harness):
            "the \(harness) harness is not authenticated (no usable credential)"
        case let .skillNotVisible(skill, reason):
            "skill \(skill) is not visible to the harness: \(reason)"
        case let .baselineNotIsolable(harness, reason):
            "the \(harness) harness cannot prove a skill-free baseline for --ab: \(reason)"
        case let .invalidArtifact(path, reason):
            "\(path) is invalid: \(reason)"
        case let .sanitizerNotFound(reason):
            "the secret scanner could not run, so capture will not write an unscrubbed bundle: \(reason)"
        case let .captureDestinationExists(paths):
            "capture destination already exists: \(paths.joined(separator: ", "))"
        case let .sessionNotFound(workspace):
            "no claude-code session found for \(workspace) — nothing to capture"
        }
    }

    /// The env-var fragment for a harness id (`claude-code` → `CLAUDE_CODE`), so remedies print the
    /// real, copy-pasteable variable name rather than a `<ID>` placeholder (P6).
    static func envID(_ harness: String) -> String {
        harness.uppercased().replacing("-", with: "_")
    }

    /// The exact next action that fixes the error.
    public var remedy: String {
        switch self {
        case let .usage(_, remedy):
            remedy
        case .directoryNotFound:
            "pass an existing, readable directory to -C, or omit -C to use the current directory"
        case .pathNotFound:
            "pass an existing, readable file or directory to `skillet score`"
        case .projectNotFound:
            "run from inside a skills repository, or initialize one with `skillet init`"
        case let .harnessNotFound(harness):
            "install \(harness), or set its path via --harness-path, SKILLET_\(Self.envID(harness))_BIN, or harness.\(harness).path"
        case let .harnessBanned(harness, _):
            "pin a non-banned version, or set SKILLET_ALLOW_BANNED_\(Self.envID(harness))=1 to override deliberately"
        case let .harnessUnauthenticated(harness):
            "authenticate \(harness) (e.g. `claude auth login`, or set ANTHROPIC_API_KEY / CLAUDE_CODE_OAUTH_TOKEN), then re-run"
        case .skillNotVisible:
            "check the skill directory has a SKILL.md (and references/) resolvable under the harness"
        case let .baselineNotIsolable(harness, _):
            "pin a \(harness) version that supports session-level skill disabling (SKILLET_\(Self.envID(harness))_BIN), or run without --ab"
        case .invalidArtifact:
            "fix or regenerate the file so it matches its schema (see skillet-design §7)"
        case .sanitizerNotFound:
            "install betterleaks, or set its path via --secret-scanner-path, SKILLET_BETTERLEAKS_BIN, or sanitize.scanner_path"
        case .captureDestinationExists:
            "re-run with --force to overwrite, or choose a different --slug"
        case .sessionNotFound:
            "run the work in that directory first, or pass --session <id>; check --target-dir points at the workspace"
        }
    }
}
