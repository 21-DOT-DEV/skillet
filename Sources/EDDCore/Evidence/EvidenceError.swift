import Foundation

/// Domain errors from reading/validating an evidence record — **pure**, with no YAML/frontmatter
/// concept (that stays at the `ConfigYAML` seam's `ConfigError`; D4/nit-3). Not for direct user
/// rendering: the `friction`/`triage` commands translate these at the boundary into `EDDError` cases
/// carrying an exit code + remedy (the `CorpusError`→`EDDError` pattern).
public enum EvidenceError: Error, Sendable, Equatable {
    /// `schema:` is absent or not one of the recognized evidence formats.
    case unknownSchema(String)
    /// A required field is missing (the field name is included).
    case missingField(String)
    /// A field carries a value the schema doesn't allow (a bad enum, a malformed `id`, a non-string
    /// `sessions` element). `field` names it; `value` is the offending text.
    case invalidValue(field: String, value: String)
    /// `state` is a human-set decision state (`held`/`watch`/`closed`) but its `state_reason` is missing
    /// or empty — §6.1 `set-state` takes a required `--reason` for all three (D5).
    case missingStateReason(state: LifecycleState)
    /// The frontmatter `id` disagrees with the file's own name stem (F4).
    case idMismatch(id: String, filename: String)
    /// A status change the lifecycle forbids (D1) — raised at *write* time by the commands, not on read.
    case illegalTransition(from: LifecycleState, to: LifecycleState)
}
