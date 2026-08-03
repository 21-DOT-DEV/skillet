import Foundation

/// One skipped/refused input, named with its reason — the "every omission is disclosed" rule every
/// reporting command follows. Format-neutral on purpose: `triage` and `suggest` both embed it, so it
/// carries no command in its name. `TriageDisclosure` remains as a source-compatible alias (the JSON is
/// identical either way — a bare `{subject, reason}` object).
public struct Disclosure: Codable, Sendable, Equatable {
    public let subject: String
    public let reason: String
    public init(subject: String, reason: String) { self.subject = subject; self.reason = reason }
}
