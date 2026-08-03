import Foundation

/// The one place the project states **when two evidence records are related**: they were produced in the
/// same recorded session.
///
/// This is deliberately tiny, and deliberately shared. "Don't repeat yourself" is about a piece of
/// *knowledge* having one authoritative representation — and this rule is knowledge: a documented design
/// decision (relate findings and human notes by shared session, computed live rather than stored). Both
/// `triage` and `suggest` implement that same rule, so it lives here once; if it ever changes — matching
/// by prefix, or within a time window — there is exactly one line to change instead of two that drift.
///
/// What is **not** shared, on purpose: each caller's own filtering, input types, and return shape. Those
/// differ genuinely (one returns records and excludes already-named ids; the other returns identifiers),
/// and folding them together would mean parameters plus conditional paths to serve two callers — the
/// signature of a wrong abstraction, where duplication would have been the cheaper choice.
public enum EvidenceLink {
    /// True when the two sets of recorded-session ids overlap at all.
    public static func sharesSession(_ lhs: some Sequence<String>, _ rhs: some Sequence<String>) -> Bool {
        !Set(lhs).isDisjoint(with: Set(rhs))
    }
}
