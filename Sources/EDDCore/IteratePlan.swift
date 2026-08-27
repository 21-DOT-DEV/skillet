import Foundation

/// The `--json --dry-run` payload for the proving command (`skillet.iterate-plan/1`): a **spend-free
/// preview** of what proving an edit would cost, and deliberately *not* a measured result (that is
/// ``IterateReport`` / `skillet.iterate/1`).
///
/// **Why it exists.** Every command here offers a machine-readable form, and every machine-readable
/// payload carries a schema — but this command's preview hand-assembled prose and ignored the request
/// for one, so a script asking for a plan received a table meant for a person and had to read it by eye.
/// Its sibling has answered this correctly since it shipped (``RunPlan``); this is the same idea for the
/// command that measures twice.
///
/// Kept small and **non-volatile** — no timestamps and no paths that differ between machines.
public struct IteratePlan: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.iterate-plan/1"

    public let skill: String
    /// The draft being proven, as named on the command line.
    public let proposals: String
    /// Which of the draft's edits would be proven, numbered from 0 in draft order.
    public let edits: [Int]
    public let evals: Int
    public let k: Int
    /// Total trials — **both measurements**, so twice what a single measurement of the same tests costs.
    public let trials: Int
    public let confirmAboveTrials: Int
    /// `trials > confirm_above_trials` — a real run would put the cost to you first.
    public let requiresConfirmation: Bool
    /// Whether a real run would call a model (false under the offline test seam).
    public let willSpend: Bool
    /// Estimated model calls: one answer and one grading per trial.
    public let estimatedCalls: Int

    public init(skill: String, proposals: String, edits: [Int], evals: Int, k: Int, trials: Int,
                confirmAboveTrials: Int, requiresConfirmation: Bool, willSpend: Bool,
                estimatedCalls: Int) {
        self.skill = skill
        self.proposals = proposals
        self.edits = edits
        self.evals = evals
        self.k = k
        self.trials = trials
        self.confirmAboveTrials = confirmAboveTrials
        self.requiresConfirmation = requiresConfirmation
        self.willSpend = willSpend
        self.estimatedCalls = estimatedCalls
    }
}
