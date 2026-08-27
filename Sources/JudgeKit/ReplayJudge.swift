import Foundation
import EDDCore

/// A deterministic ``Judge`` for tests and CI — it grades from a fixed `criterion → passed` map and
/// never shells a model, so `skillet run`'s loop is provable end-to-end with no live judge. The
/// *public* `--replay` capture/replay path is F19; F7 uses this only behind the test seam.
public struct ReplayJudge: Judge {
    let verdicts: [String: Bool]
    let defaultPass: Bool

    public init(_ verdicts: [String: Bool] = [:], defaultPass: Bool = false) {
        self.verdicts = verdicts
        self.defaultPass = defaultPass
    }

    /// **Matched on the answer as well as the criterion, and never on a guess.**
    ///
    /// Matching on the criterion alone is the same shape as a recorded-response tool matching a web
    /// request on its address while ignoring what was sent — it cannot tell two different answers apart,
    /// which every such tool lets you widen for exactly this reason. Here the narrow key made it
    /// impossible to test a command that measures a skill, edits it, and measures again: both
    /// measurements graded identically no matter what changed.
    ///
    /// A key of `<criterion> @ <marker>` wins when the answer contains that marker; the bare criterion is
    /// still consulted, so every recording written before this behaves exactly as it did.
    /// The marker the stand-in put in this reply, recovered **exactly** rather than searched for.
    ///
    /// The stand-in writes its answer as `<text> [<marker>]`, so the marker is everything between the
    /// first `" ["` and the closing bracket at the end. Reading it back that way makes matching an
    /// equality test, which is what removes the defect: searching the reply for the marker text meant a
    /// shorter recorded marker fitted inside a longer real one — `v1` inside `v1 release` — and two
    /// recorded answers matched at once. Which of them won was then decided by the order a lookup table
    /// happened to be in, and Swift randomises that per run on purpose; twenty identical runs of one
    /// command split ten and ten between opposite verdicts.
    ///
    /// **With an equality test, two recorded answers cannot both fit** — the reply carries exactly one
    /// marker and recorded answers are unique — so there is no tie left to break and no refusal to write.
    /// That is why you will not find one here: unreachable code that looks like a safety net is worse
    /// than none, because it reads as cover it does not give.
    static func marker(in responseText: String) -> String? {
        guard responseText.hasSuffix("]"), let open = responseText.range(of: " [") else { return nil }
        return String(responseText[open.upperBound..<responseText.index(before: responseText.endIndex)])
    }

    public func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict {
        // One reply carries one marker, and a recorded answer applies only if its marker is that one.
        let specific = Self.marker(in: evidence.responseText).flatMap { verdicts["\(criterion) @ \($0)"] }
        let passed = specific ?? verdicts[criterion] ?? defaultPass
        return Verdict(
            criterion: criterion, passed: passed, rationale: passed ? "replay: pass" : "replay: fail",
            judgeId: "replay", model: "replay", judgePromptVersion: "replay"
        )
    }
}
