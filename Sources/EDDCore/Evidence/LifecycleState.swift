import Foundation

/// How far along a piece of evidence is (design §7.3, F29). The main path is `logged → candidate →
/// codified → proven → closed`; `watch`/`held` are **human-set side states**. A typed enum makes an
/// illegal *value* unrepresentable in code — a hand-edited bogus `state:` fails loud on decode (D1).
public enum LifecycleState: String, Codable, Sendable, Equatable, CaseIterable {
    case logged, candidate, codified, proven, closed
    case watch, held
}

/// The evidence lifecycle's legal-moves table + validator (D1). Transitions are **domain logic**,
/// centralized here so design D6 — "a status never transitions implicitly" — is a *unit-tested property
/// of the core*, not a convention each command re-implements. The future commands (F30 `set-state`,
/// `next`, `eval new --from-friction`, `iterate --mark`) route every status change through `validate`
/// before writing; the write itself is the command's, after (side effects stay out of the decision).
public enum EvidenceLifecycle {
    /// Allowed next states from each state (Unknown 1 = Option A **+ one reopen edge**, 2026-07-17): the
    /// forward path + human side states, plus the **backward moves** the workflow needs — a `candidate →
    /// logged` revert and the `watch`/`held → logged`/`candidate` returns — and, uniquely out of the
    /// **terminal** `closed`, the `closed → logged` **reopen** by which a recurring friction / re-detected
    /// finding re-enters the pipeline (rather than spawning a duplicate that loses the corroboration
    /// count). Deliberately excluded: a direct `watch ↔ held` swap, and any `codified`/`proven → earlier`
    /// revert (a regressed item goes to `held`/`closed`, never silently back-steps its forward progress —
    /// advancement stays auditable).
    static let allowed: [LifecycleState: Set<LifecycleState>] = [
        .logged:    [.candidate, .watch, .held, .closed],
        .candidate: [.codified, .watch, .held, .closed, .logged],
        .codified:  [.proven, .held, .closed],
        .proven:    [.closed, .held],
        .watch:     [.logged, .candidate, .closed],
        .held:      [.logged, .candidate, .closed],
        .closed:    [.logged],   // reopen — the only exit from the terminal `closed` (other backward moves are non-terminal)
    ]

    /// Whether `from → to` is a legal move. A **self-transition** (`X → X`) is never legal — encoding
    /// "no silent no-op, no implicit change".
    public static func canTransition(from: LifecycleState, to: LifecycleState) -> Bool {
        from != to && (allowed[from]?.contains(to) ?? false)
    }

    /// Throwing form for the commands: an illegal or self-transition throws `illegalTransition`.
    public static func validate(from: LifecycleState, to: LifecycleState) throws {
        guard canTransition(from: from, to: to) else {
            throw EvidenceError.illegalTransition(from: from, to: to)
        }
    }
}
