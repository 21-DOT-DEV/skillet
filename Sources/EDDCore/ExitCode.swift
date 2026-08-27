/// The process exit codes skillet returns. **Stable API** (design §5.4): scripts and CI depend on
/// these values, so they never change without a major version bump.
public enum ExitCode: Int32, Sendable, CaseIterable {
    /// Success; everything measured passed.
    ///
    /// **`iterate` is narrower**, and says so in the design table it mirrors (§5.4): it leaves `0` when
    /// no test scored *lower* than before the edit, which can include a skill whose tests were already
    /// failing. Spelled out because the plain wording above is false for that command — a reader who
    /// takes `0` to mean "everything passed" would read a proven edit as a passing suite.
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
    ///
    /// **Also: this machine could not give a clean without-skill comparison.** `run --ab` adds a second
    /// measurement with the skill switched off. A free check before any spending refuses here when the
    /// model program cannot switch skills off at all; the same number is now left when that check passed
    /// but the comparison still came back with no usable pairing — every attempt failed, or a skill fired
    /// where none may exist. It is not `1`, because no test failed; the with-skill results are written
    /// and valid, and what could not be produced is the comparison you asked for. Exit `0` on the
    /// remaining `--ab` runs therefore means the tests passed **and** a comparison was drawn.
    case environment = 3
    /// Artifact error: a corrupt/invalid file against its schema.
    case artifact = 4
    /// **A safety gate refused, and nothing was done.** Not a broken file and not a broken machine —
    /// a deliberate check said no. Used by the drafting size ceiling; by an apply that found the
    /// repository dirty or an edit no longer matching; and by a declined cost confirmation in the
    /// proving command, where nothing was mistyped and nothing was done (Specs/020 D8 — the measuring
    /// command leaves `2` there, which predates this table and is recorded as a disagreement rather
    /// than copied). (It predates all of them; the earlier note said "under `--strict`", which was
    /// already narrower than its only use.)
    case gate = 5
    /// **Nothing could be measured, and trying again may well work.** Left when attempts were never
    /// graded — the grader errored, a rate limit hit, the connection dropped — and nothing that *was*
    /// graded failed. A real measured failure still wins and leaves `1`, because that is genuine
    /// information about the skill.
    ///
    /// **Deliberately not `3`.** That number means the environment is wrong — a missing program, absent
    /// credentials — and running again never fixes it. This does usually fix itself on a retry. Behind one
    /// number, a pipeline set to retry would keep re-running a missing binary that can never succeed, and
    /// one set not to retry would never re-run the rate limit that would have.
    ///
    /// 75 is the long-standing Unix number for exactly this, documented as "a temporary failure … the
    /// request should be reattempted later" (`sysexits`), and continuous-integration systems can already
    /// be told to retry on a specific exit number. Additive, like 70 above: no existing code changes
    /// meaning, and anything treating non-zero as failure is unaffected.
    case temporaryFailure = 75
    /// **Internal error — a defect in skillet itself**, not the user's input, files, or environment.
    /// 70 is the long-standing Unix convention for "internal software error" (`sysexits`), so a script
    /// or CI job can tell a tool bug apart from a real problem with the project. Additive: no existing
    /// code changes meaning. Reaching this always means we owe someone a fix, never that they did
    /// something wrong — the message says so and points at where to report it.
    case internalError = 70
}
