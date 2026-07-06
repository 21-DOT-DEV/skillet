import Foundation

/// One trial of one trigger case (F14): did the **target** skill fire, judged deterministically from
/// `Trace.skillInvocations` — no judge (design §9.3). `firedOther` records sibling fires for routing
/// forensics: under the D-3 attribution rule a near-miss (`should_trigger: false`) that routes to a
/// sibling is *correct* non-firing, and knowing where it went is the description-debugging signal.
public struct TriggerTrialResult: Codable, Sendable, Equatable {
    public let exit: TrialExit
    public let firedTarget: Bool
    public let firedOther: [String]

    public init(exit: TrialExit, firedTarget: Bool, firedOther: [String] = []) {
        self.exit = exit
        self.firedTarget = firedTarget
        self.firedOther = firedOther
    }
}

/// All recorded trials for one trigger case. Pass semantics mirror the behavioral axis (§4 is
/// axis-generic): a trial passes iff it ran cleanly **and** the target's firing matched
/// `should_trigger`; `PassK.status` then yields PASS/FAIL/FLAKY on the case's own recorded count.
public struct TriggerEvalResult: Codable, Sendable, Equatable {
    public let evalId: String
    public let query: String
    public let shouldTrigger: Bool
    public let trials: [TriggerTrialResult]

    public init(evalId: String, query: String, shouldTrigger: Bool, trials: [TriggerTrialResult]) {
        self.evalId = evalId
        self.query = query
        self.shouldTrigger = shouldTrigger
        self.trials = trials
    }

    public var recorded: Int { trials.count }
    public var passes: Int {
        trials.filter { $0.exit == .passed && $0.firedTarget == shouldTrigger }.count
    }
}
