/// The process exit codes skillet returns. **Stable API** (design §5.4): scripts and CI depend on
/// these values, so they never change without a major version bump.
public enum ExitCode: Int32, Sendable, CaseIterable {
    /// Success; everything measured passed.
    case success = 0
    /// Measured failure: eval failures, trigger misfires, `iterate` regression — **and a paid drafting
    /// run that came back proposing no change.** That last one is the same shape as the others: the
    /// command ran correctly and the answer was negative, which is neither success nor an error. It is
    /// spelled out here because the alternative was reporting success, which let a script chain
    /// "draft, then apply" straight into a refusal — the long-standing convention for this is the search
    /// tool that returns 0 for a match, 1 for ran-fine-found-nothing, and 2 for could-not-search.
    case measuredFailure = 1
    /// Usage error: bad flags or arguments.
    case usage = 2
    /// Environment error: harness missing, auth failure, `doctor` failure, missing project context.
    case environment = 3
    /// Artifact error: a corrupt/invalid file against its schema.
    case artifact = 4
    /// **A safety gate refused, and nothing was done.** Not a broken file and not a broken machine —
    /// a deliberate check said no. Used by the drafting size ceiling and by an apply that found the
    /// repository dirty or an edit no longer matching. (It predates both; the earlier note said
    /// "under `--strict`", which was already narrower than its only use.)
    case gate = 5
    /// **Internal error — a defect in skillet itself**, not the user's input, files, or environment.
    /// 70 is the long-standing Unix convention for "internal software error" (`sysexits`), so a script
    /// or CI job can tell a tool bug apart from a real problem with the project. Additive: no existing
    /// code changes meaning. Reaching this always means we owe someone a fix, never that they did
    /// something wrong — the message says so and points at where to report it.
    case internalError = 70
}
