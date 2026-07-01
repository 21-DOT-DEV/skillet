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

    public func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict {
        let passed = verdicts[criterion] ?? defaultPass
        return Verdict(
            criterion: criterion, passed: passed, rationale: passed ? "replay: pass" : "replay: fail",
            judgeId: "replay", model: "replay", judgePromptVersion: "replay"
        )
    }
}
