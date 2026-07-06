import Foundation

/// The `--json --dry-run` payload (`skillet.run-plan/1`): a **spend-free preview** of what `skillet run`
/// would do — deliberately *not* a measured result (that's ``RunReport`` / `skillet.run/1`). Emitting it
/// keeps the "every `--json` path is schema-stamped" contract for the `--json --dry-run` combination,
/// giving CI a machine-readable estimate.
///
/// Kept small and **non-volatile** — no timestamps, resolved binary path, or cost figures (real cost
/// estimates, once they exist, arrive as *additive* optional fields like `estimated_cost`).
public struct RunPlan: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.run-plan/1"

    public let skill: String
    public let evals: Int
    public let k: Int
    /// Total trials across axes (behavioral + trigger) — the number the spend gate compares.
    public let trials: Int
    public let confirmAboveTrials: Int
    /// `trials > confirm_above_trials` — the real run would need spend confirmation.
    public let requiresConfirmation: Bool
    /// Whether a real (non-dry-run) execution would call the model (false under the replay seam).
    public let willSpend: Bool
    /// Trigger-axis case/trial counts (F14) — additive; `nil` (keys absent) when the axis won't run.
    public let triggerCases: Int?
    public let triggerTrials: Int?
    /// Estimated model calls (F14 review round 2, additive): behavioral trials × 2 (task + judge) +
    /// trigger trials × 1 (deterministic, no judge). **Informative** — the confirmation gate stays
    /// trial-denominated (`confirm_above_trials` has meant trials since it shipped; decided
    /// in-session 2026-07-05); this field makes the cost visible before consent (P9).
    public let estimatedCalls: Int?

    public init(skill: String, evals: Int, k: Int, trials: Int, confirmAboveTrials: Int, requiresConfirmation: Bool, willSpend: Bool, triggerCases: Int? = nil, triggerTrials: Int? = nil, estimatedCalls: Int? = nil) {
        self.skill = skill
        self.evals = evals
        self.k = k
        self.trials = trials
        self.confirmAboveTrials = confirmAboveTrials
        self.requiresConfirmation = requiresConfirmation
        self.willSpend = willSpend
        self.triggerCases = triggerCases
        self.triggerTrials = triggerTrials
        self.estimatedCalls = estimatedCalls
    }
}
