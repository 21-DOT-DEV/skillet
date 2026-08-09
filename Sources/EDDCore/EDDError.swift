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
    /// The harness is the obstacle. `reason` is `nil` when we genuinely could not find the program;
    /// otherwise it says what went wrong with a program we DID find (a failed call, a timeout, a refused
    /// launch). One concept, accurate specifics — the previous single fixed message claimed "could not
    /// find it" for every case, so a sign-in or quota failure told people to install software they had.
    case harnessNotFound(harness: String, reason: String?)
    /// An explicitly pinned harness binary is on the denylist. Exit ``ExitCode/environment``.
    case harnessBanned(harness: String, version: String)
    /// The harness resolved + ran but is not authenticated (e.g. `claude auth status` reports logged-out).
    /// Exit ``ExitCode/environment`` — caught at preflight, before any paid trial.
    case harnessUnauthenticated(harness: String)
    /// A skill is not visible to the harness under its injection strategy. Exit ``ExitCode/environment``.
    /// `fix` follows the same rule as ``invalidArtifact(path:reason:fix:)``: `nil` keeps the standard
    /// advice, which suits a skill file that is simply absent. It exists because the same error also
    /// reports a file refused for being too large, or for sitting outside the project, and telling
    /// someone to check the folder has a skill file is no help when the file is right there.
    case skillNotVisible(skill: String, reason: String, fix: String?)
    /// The harness cannot prove a skill-free baseline arm (`--ab`, §9.2: isolate ambient skills or
    /// declare it cannot) — refused before spend, never a polluted baseline. Exit ``ExitCode/environment``.
    case baselineNotIsolable(harness: String, reason: String)
    /// A committed artifact is corrupt/invalid against its schema (e.g. unparseable `evals.json`).
    /// Exit ``ExitCode/artifact``.
    /// `fix` is what to actually do, when the standard advice below would be wrong. Most uses of this
    /// error really are "the file's contents are the wrong shape", and for those the standard line is
    /// right and `fix` stays `nil`. But the same error also rejects a path because part of it is a
    /// pointer to somewhere else on disk, a folder that turned out to be a file, and a name that does not
    /// match — none of which are fixed by editing a file to match a schema, and all of which were told to
    /// do exactly that. Advice for the wrong problem sends people to look where the problem is not.
    ///
    /// Caller-supplied rather than worked out here, because only the place that raised it knows: the
    /// house rule is to match a refusal's *case* and never its wording, so reading the advice off the
    /// message text would be exactly the mistake this codebase already warns against.
    case invalidArtifact(path: String, reason: String, fix: String?)
    /// The secret scanner (`betterleaks`) could not be resolved or run, so `capture` cannot prove the
    /// bundle was scrubbed — it fails closed rather than write an unsanitized bundle (constitution VI).
    /// Exit ``ExitCode/environment``.
    case sanitizerNotFound(reason: String)
    /// One or more `capture` bundle files already exist and `--force` was not given. Exit ``ExitCode/environment``.
    case captureDestinationExists(paths: [String])
    /// `capture` found no native session for the workspace. Exit ``ExitCode/environment``.
    case sessionNotFound(workspace: String)
    /// A spend/safety gate refused before any paid work (e.g., the prompt ceiling without `--yes`).
    /// Exit ``ExitCode/gate``.
    case gate(message: String, remedy: String)
    /// An error we did not anticipate. Carries the underlying text so the defect is diagnosable.
    case internalError(detail: String)
    /// The operating system refused a write we need — permissions, disk space, an I/O fault. The
    /// machine is the obstacle, not the project's contents, so this is an environment problem.
    /// **A write this tool needed to make was refused by the machine** — permissions, a full disk, a
    /// read-only mount. Covers the scratch folder it manages *and* a skill file it was asked to change:
    /// the reaction is identical either way, which is why they share one label rather than having a
    /// near-duplicate each. The name says "cache" because that was its first use; it is part of the
    /// published set of error labels, which only ever grows, so renaming it would break anything
    /// matching on it. The human message always names the actual file, so nobody is told "cache" about
    /// a file they keep in version control.
    case cacheUnwritable(path: String, reason: String)

    /// The spelling for the common case: the file's contents are the wrong shape, so the standard advice
    /// applies. Exists so adding per-place advice did not mean editing every one of the places that
    /// never needed it — churn that would have buried the handful of messages this actually fixes.
    public static func invalidArtifact(path: String, reason: String) -> EDDError {
        .invalidArtifact(path: path, reason: reason, fix: nil)
    }

    /// Same purpose as the overload above, for the same reason.
    public static func skillNotVisible(skill: String, reason: String) -> EDDError {
        .skillNotVisible(skill: skill, reason: reason, fix: nil)
    }

    /// The stable exit code for this error.
    public var exitCode: ExitCode {
        switch self {
        case .usage: .usage
        case .directoryNotFound, .pathNotFound, .projectNotFound, .harnessNotFound, .harnessBanned, .harnessUnauthenticated, .skillNotVisible, .baselineNotIsolable, .sanitizerNotFound, .captureDestinationExists, .sessionNotFound: .environment
        case .invalidArtifact: .artifact
        case .gate: .gate
        case .internalError: .internalError
        case .cacheUnwritable: .environment
        }
    }

    /// A machine-stable identifier for the error class (used in `skillet.error/1`).
    public var kind: String {
        switch self {
        case .usage: "usage"
        case .directoryNotFound: "directory_not_found"
        case .pathNotFound: "path_not_found"
        case .projectNotFound: "project_not_found"
        case let .harnessNotFound(_, reason): reason == nil ? "harness_not_found" : "harness_unavailable"
        case .harnessBanned: "harness_banned"
        case .harnessUnauthenticated: "harness_unauthenticated"
        case .skillNotVisible: "skill_not_visible"
        case .baselineNotIsolable: "baseline_not_isolable"
        case .invalidArtifact: "invalid_artifact"
        case .sanitizerNotFound: "sanitizer_not_found"
        case .captureDestinationExists: "capture_destination_exists"
        case .sessionNotFound: "session_not_found"
        case .gate: "gate"
        case .internalError: "internal_error"
        case .cacheUnwritable: "cache_unwritable"
        }
    }

    /// Human-readable "what went wrong, and why".
    public var message: String {
        switch self {
        case let .internalError(detail):
            "internal error — this is a defect in skillet, not a problem with your project: \(detail)"
        case let .cacheUnwritable(path, reason):
            "could not write \(path): \(reason)"
        case let .usage(message, _):
            message
        case let .directoryNotFound(path):
            "the directory passed to -C does not exist or is not readable: \(path)"
        case let .pathNotFound(path):
            "the path to score does not exist or is not readable: \(path)"
        case let .projectNotFound(cwd):
            "no skillet project found from \(cwd) (no skillet.yaml or .git boundary up the tree)"
        case let .harnessNotFound(harness, reason):
            reason.map { "the \(harness) harness could not be used: \($0)" }
                ?? "could not find the \(harness) binary (checked the flag, env, config, and PATH)"
        case let .harnessBanned(harness, version):
            "the pinned \(harness) version \(version) is on the denylist (known-bad)"
        case let .harnessUnauthenticated(harness):
            "the \(harness) harness is not authenticated (no usable credential)"
        case let .skillNotVisible(skill, reason, _):
            "skill \(skill) is not visible to the harness: \(reason)"
        case let .baselineNotIsolable(harness, reason):
            "the \(harness) harness cannot prove a skill-free baseline for --ab: \(reason)"
        case let .invalidArtifact(path, reason, _):
            "\(path) is invalid: \(reason)"
        case let .sanitizerNotFound(reason):
            "the secret scanner could not run, so capture will not write an unscrubbed bundle: \(reason)"
        case let .captureDestinationExists(paths):
            "capture destination already exists: \(paths.joined(separator: ", "))"
        case let .sessionNotFound(workspace):
            "no claude-code session found for \(workspace) — nothing to capture"
        case let .gate(message, _):
            message
        }
    }

    /// The env-var fragment for a harness id (`claude-code` → `CLAUDE_CODE`), so remedies print the
    /// real, copy-pasteable variable name rather than a `<ID>` placeholder (P6).
    static func envID(_ harness: String) -> String {
        harness.uppercased().replacing("-", with: "_")
    }

    /// What to do about a program we *found* and then could not use. It has to depend on which program,
    /// because the ways they fail have nothing in common: a model harness fails over sign-in, spending
    /// limits, or a mistyped model name, while `git` fails over a missing repository, a damaged index, or
    /// a lock another process is holding. One sentence covered both, so every git failure — including
    /// being run outside a repository at all — advised checking you were signed in and that your model
    /// name was valid. Advice for the wrong program is worse than none: it sends you to look where the
    /// problem is not. Naming programs here matches how the rest of these remedies already work (the
    /// sign-in one names `claude auth login` and its environment variables).
    static func whenTheProgramFailed(_ harness: String) -> String {
        switch harness {
        case "git":
            // True of every git failure this can report — not installed, not a repository, unreadable
            // index — and it hands over the one command whose own output says which.
            "check git is installed and that `git status` works in this folder, then re-run"
        default:
            "check you are signed in, that you are within any usage limits, and that the configured model name is valid"
        }
    }

    /// The exact next action that fixes the error.
    public var remedy: String {
        switch self {
        case .internalError:
            "please report it at https://github.com/21-DOT-DEV/skillet/issues with the command you ran"
        case .cacheUnwritable:
            "check the directory's write permissions and available disk space, then re-run"
        case let .usage(_, remedy):
            remedy
        case .directoryNotFound:
            "pass an existing, readable directory to -C, or omit -C to use the current directory"
        case .pathNotFound:
            "pass an existing, readable file or directory to `skillet score`"
        case .projectNotFound:
            "run from inside a skills repository, or initialize one with `skillet init`"
        case let .harnessNotFound(harness, reason):
            reason == nil
                ? "install \(harness), or set its path via --harness-path, SKILLET_\(Self.envID(harness))_BIN, or harness.\(harness).path"
                : Self.whenTheProgramFailed(harness)
        case let .harnessBanned(harness, _):
            "pin a non-banned version, or set SKILLET_ALLOW_BANNED_\(Self.envID(harness))=1 to override deliberately"
        case let .harnessUnauthenticated(harness):
            "authenticate \(harness) (e.g. `claude auth login`, or set ANTHROPIC_API_KEY / CLAUDE_CODE_OAUTH_TOKEN), then re-run"
        case let .skillNotVisible(_, _, fix):
            fix ?? "check the skill directory has a SKILL.md (and references/) resolvable under the harness"
        case let .baselineNotIsolable(harness, _):
            "pin a \(harness) version that supports session-level skill disabling (SKILLET_\(Self.envID(harness))_BIN), or run without --ab"
        case let .invalidArtifact(_, _, fix):
            fix ?? "fix or regenerate the file so it matches its schema (see skillet-design §7)"
        case .sanitizerNotFound:
            "install betterleaks, or set its path via --secret-scanner-path, SKILLET_BETTERLEAKS_BIN, or sanitize.scanner_path"
        case .captureDestinationExists:
            "re-run with --force to overwrite, or choose a different --slug"
        case .sessionNotFound:
            "run the work in that directory first, or pass --session <id>; check --target-dir points at the workspace"
        case let .gate(_, remedy):
            remedy
        }
    }
}
