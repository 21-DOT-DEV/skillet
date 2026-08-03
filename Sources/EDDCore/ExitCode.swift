/// The process exit codes skillet returns. **Stable API** (design §5.4): scripts and CI depend on
/// these values, so they never change without a major version bump.
public enum ExitCode: Int32, Sendable, CaseIterable {
    /// Success; everything measured passed.
    case success = 0
    /// Measured failure: eval failures, trigger misfires, `iterate` regression.
    case measuredFailure = 1
    /// Usage error: bad flags or arguments.
    case usage = 2
    /// Environment error: harness missing, auth failure, `doctor` failure, missing project context.
    case environment = 3
    /// Artifact error: a corrupt/invalid file against its schema.
    case artifact = 4
    /// Gate violation under `--strict`.
    case gate = 5
    /// **Internal error — a defect in skillet itself**, not the user's input, files, or environment.
    /// 70 is the long-standing Unix convention for "internal software error" (`sysexits`), so a script
    /// or CI job can tell a tool bug apart from a real problem with the project. Additive: no existing
    /// code changes meaning. Reaching this always means we owe someone a fix, never that they did
    /// something wrong — the message says so and points at where to report it.
    case internalError = 70
}
