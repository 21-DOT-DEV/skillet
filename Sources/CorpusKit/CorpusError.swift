/// Domain errors from the bundle writer/reader — like `HarnessError`, they are translated at the
/// `capture` command boundary into user-facing `EDDError` cases (exit code + remedy).
public enum CorpusError: Error, Sendable, Equatable {
    /// One or more bundle files already exist and `--force` was not given (carries the filenames).
    /// The command maps this to exit 3 with a "re-run with --force" remedy.
    case destinationExists(paths: [String])
    /// A bundle file could not be encoded or written.
    case writeFailed(path: String, reason: String)
}
