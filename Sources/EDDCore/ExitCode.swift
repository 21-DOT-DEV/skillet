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
}
