import Foundation
import EDDCore
import HarnessKit
import JudgeKit
import RunKit
import ConfigYAML

/// Choosing the program that answers and the grader that marks the answers — the part every command
/// that measures behaviour needs, and needs identically.
///
/// **Why one place.** A program has one spot where its parts are wired together; scattering that across
/// commands is how two of them drift while both keep working. The risk is not a wiring that is wrong
/// today — that would fail immediately and loudly — but two wirings that stop agreeing about which
/// grader, which model, or which refusal comes first, months apart.
///
/// **Why only the common part.** The measuring command also builds a second grader for its
/// switched-off arm, and skips the grader entirely for its deterministic axis. Neither has a second
/// caller, and folding them in here would mean settings this routine's other caller never uses — a
/// routine you cannot read at the call site without remembering what each one means. So those stay
/// where they are used, and what moves is what must never differ.
enum MeasurementSetup {
    /// What a measurement needs, once the choices are made.
    struct Wiring {
        let adapter: any HarnessAdapter
        let judge: any Judge
        /// Provenance stamped into records so a result can say what produced it.
        let id: String
        let provider: String
        let model: String
        let promptVersion: String
        let policy: EvidencePolicy
    }

    /// Canned verdicts standing in for a grader, so tests cost nothing. `defaultPass` decides what an
    /// unlisted criterion gets — `true` when no recording was supplied at all.
    struct Offline {
        let verdicts: [String: Bool]
        let defaultPass: Bool
    }

    /// `offline` non-nil swaps both the program and the grader for stand-ins and skips every check that
    /// only matters when real money is involved.
    ///
    /// **`approved` is not decoration — it is the only way in.** The time limit and the output cap come
    /// out of it rather than being passed separately, so this cannot be called with numbers that were
    /// never checked. A future paid command that skips the settings gate has nothing to hand over here
    /// and does not compile; see `SpendGate.Approved`.
    static func forBehaviour(config: SkilletConfig?, judge judgeCfg: SkilletConfig.Judge,
                             approved: SpendGate.Approved, judgeSelection: String,
                             offline: Offline?) throws -> Wiring {
        let timeout = approved.timeout
        let outputLimitBytes = approved.outputLimitBytes
        // The grounded grader reads the files a run produced; that policy follows the selection even
        // offline, so the capture path is exercised without paying while the grading stays canned.
        let policy: EvidencePolicy = (judgeSelection == GroundedJudge.id) ? .groundedDefault : .listingOnly
        if let offline {
            return Wiring(adapter: ReplayAdapter(),
                          judge: ReplayJudge(offline.verdicts, defaultPass: offline.defaultPass),
                          id: "replay", provider: "replay", model: "replay", promptVersion: "replay",
                          policy: policy)
        }
        guard judgeCfg.provider == "claude-code" else {
            throw EDDError.usage(
                message: "judge.provider '\(judgeCfg.provider)' is not supported in Phase 1",
                remedy: "set judge.provider: claude-code in skillet.yaml (the only implemented provider)"
            )
        }
        guard let model = judgeCfg.model?.trimmingCharacters(in: .whitespaces), !model.isEmpty else {
            throw EDDError.usage(
                message: "judge.model is not set — a paid run needs an explicit judge model so verdicts are reproducible",
                remedy: "add `model: <judge model>` under `judge:` in skillet.yaml (`skillet init` writes one)"
            )
        }
        let claudePath = config?.harness?.claudeCode?.path
        guard let resolved = BinaryResolver().resolve(flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN",
                                                      configPath: claudePath, pathName: "claude") else {
            throw EDDError.harnessNotFound(harness: "claude-code", reason: nil)
        }
        let adapter = ClaudeCodeAdapter(configPath: claudePath, timeout: timeout,
                                        outputLimitBytes: outputLimitBytes)
        let cliRunner = ClaudeCLIJudgeRunner(binaryPath: resolved.path)
        // Text (existence and claims) or grounded (reads what was produced). Same program, same
        // explicitly-required model; the difference is the prompt and the evidence.
        let selected: any Judge = (judgeSelection == GroundedJudge.id)
            ? GroundedJudge(runner: cliRunner, model: model)
            : TextJudge(runner: cliRunner, model: model)
        return Wiring(adapter: adapter, judge: selected, id: judgeSelection, provider: "claude-code",
                      model: model,
                      promptVersion: (judgeSelection == GroundedJudge.id)
                        ? GroundedJudge.promptVersion : TextJudge.promptVersion,
                      policy: policy)
    }
}
