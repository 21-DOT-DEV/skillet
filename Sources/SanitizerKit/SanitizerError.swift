/// Domain errors from the sanitizer library — like `HarnessError`/`ProcessError`, they are *not* for
/// direct user rendering. The `capture` command translates them at the boundary into user-facing
/// `EDDError` cases that carry an exit code + remedy (design §11; the codebase's hybrid error pattern).
///
/// The security contract: **any** scanner problem is fail-closed. `scannerNotFound` (can't launch the
/// binary) and `scannerUnparseable` (ran but its output isn't findings JSON) both mean "we cannot prove
/// the text was scanned," so capture must refuse to write rather than emit an unscrubbed bundle.
public enum SanitizerError: Error, Sendable, Equatable {
    /// The scanner binary could not be resolved or launched.
    case scannerNotFound(reason: String)
    /// The scanner launched but produced output we could not parse as a findings array — treated as
    /// can't-run (fail closed), **never** as "clean." (betterleaks reuses exit 1 for leaks *and* errors,
    /// so success is decided by parseable JSON, not the exit code.)
    case scannerUnparseable(reason: String)
    /// A `sanitize.exempt_paths` pattern would exempt essentially *every* artifact (e.g. `**`, `*`) — a
    /// blanket bypass. The constitution forbids a `--no-sanitize` equivalent (exemptions must be surgical),
    /// so this fails closed rather than dropping all findings and writing an unredacted bundle.
    case exemptPatternTooBroad(pattern: String)
    /// A `sanitize.exempt_paths` pattern covers one of skillet's own **synthetic artifact labels**
    /// (`transcript.md` / `diff` / `trace.json`) — the always-scanned core surfaces. Path-exempting them is
    /// a blanket bypass via config (a value-level false positive uses betterleaks' own allowlist instead).
    /// Fails closed.
    case exemptCoversSyntheticArtifact(artifact: String)
}
