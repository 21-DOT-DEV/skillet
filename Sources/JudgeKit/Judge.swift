import Foundation
import EDDCore
import TraceKit

/// What a ``Judge`` grades from — assembled by the runner after a trial completes. The judge sees the
/// run's final response, the normalized ``Trace`` (which skill fired, tools, per-turn files), and the
/// **ground-truth** post-run workspace listing. The listing is what makes a *claimed-but-not-created*
/// file judgeable: if the response says it wrote `report.md` and `report.md` is absent here, that is a
/// FAIL on existence, not on the model's say-so. File-*content* grounding (does the file say the right
/// thing) is the grounded judge, F16.
public struct JudgeEvidence: Sendable, Equatable {
    /// The run's final assistant response text.
    public let responseText: String
    /// The normalized execution trace.
    public let trace: Trace
    /// Repo-relative paths actually present in the workspace after the run — the ground truth.
    public let workspaceListing: [String]

    public init(responseText: String, trace: Trace, workspaceListing: [String]) {
        self.responseText = responseText
        self.trace = trace
        self.workspaceListing = workspaceListing
    }
}

/// Grades one criterion (one `expected_behavior` line) against a trial's ``JudgeEvidence``, yielding a
/// ``Verdict``. Effectful (a real judge shells a model) — kept behind this protocol so the runner and
/// `pass^k` math stay deterministic and the judge is swappable (text now, grounded F16, replay F19).
public protocol Judge: Sendable {
    func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict
}

/// The single "ask a model a one-shot prompt, get its text back" seam. Injected into ``TextJudge`` so
/// the prompt-building + verdict-parsing logic is unit-tested with a fake, and the real `claude`-CLI
/// runner (RunKit) is the only piece that touches a subprocess — mirroring HarnessKit's
/// `ProcessLauncher` discipline (constitution VI).
public protocol JudgeRunner: Sendable {
    func ask(prompt: String, model: String) async throws -> String
}

/// A failure of the underlying judge runner — the judge subprocess exited non-zero (auth, rate-limit,
/// model error, …). **Distinct from a judged FAIL:** it means the criterion could not be graded, so
/// the run loop classifies the trial as ungraded/failed rather than manufacturing a criterion FAIL
/// from diagnostic/empty output (preserving the measurement-vs-noise distinction).
public enum JudgeRunnerError: Error, Sendable, Equatable {
    case failed(exitCode: Int32, stderr: String)
}
