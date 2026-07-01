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
    public let trials: Int
    public let confirmAboveTrials: Int
    /// `trials > confirm_above_trials` — the real run would need spend confirmation.
    public let requiresConfirmation: Bool
    /// Whether a real (non-dry-run) execution would call the model (false under the replay seam).
    public let willSpend: Bool

    public init(skill: String, evals: Int, k: Int, trials: Int, confirmAboveTrials: Int, requiresConfirmation: Bool, willSpend: Bool) {
        self.skill = skill
        self.evals = evals
        self.k = k
        self.trials = trials
        self.confirmAboveTrials = confirmAboveTrials
        self.requiresConfirmation = requiresConfirmation
        self.willSpend = willSpend
    }
}
