import Foundation
import TraceKit

/// An in-memory `HarnessAdapter` for tests — and the proof that the seam is implementable
/// end-to-end with no live harness. Serves a deterministic synthetic `Trace`.
public struct ReplayAdapter: HarnessAdapter {
    public let id: HarnessID = "replay"
    public let capabilities: HarnessCapabilities = [.runTask, .skillInjection, .traceParsing, .baselineIsolation]
    public init() {}

    public func probe(strict: Bool) async throws -> HarnessInfo {
        HarnessInfo(id: id, version: "replay-1", authenticated: true, available: true)
    }

    public func verifySkillVisibility(_ skill: SkillRef, strategy: InjectionStrategy) throws {
        // The replay double "sees" everything — visibility always holds.
    }

    public func verifyBaselineIsolation() async throws {
        // The double is hermetic by construction — its `.none` trace fires no skill (below).
    }

    public func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
        // Arm-aware (F15): a `.none` (baseline) run must serve a skill-free session, or the §9.2
        // pollution tripwire would disqualify every replayed baseline trial.
        if case .none = skills {
            return RawTrace(harness: id, raw: "replayed-baseline: \(task.query)")
        }
        return RawTrace(harness: id, raw: "replayed: \(task.query)")
    }

    public func parseTrace(_ raw: RawTrace) throws -> Trace {
        raw.raw.hasPrefix("replayed-baseline:") ? Self.cannedBaselineTrace : Self.cannedTrace
    }

    /// A small, deterministic synthetic trace (whole-second timestamps so it round-trips exactly).
    public static let cannedTrace = Trace(
        harness: "replay",
        harnessVersion: "replay-1",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        endedAt: Date(timeIntervalSince1970: 1_700_000_060),
        turns: [
            Turn(role: .user, text: "do it", at: Date(timeIntervalSince1970: 1_700_000_000)),
            Turn(
                role: .assistant, text: "done",
                toolCalls: [ToolCall(name: "write", input: "out.txt")],
                filesTouched: ["out.txt"],
                at: Date(timeIntervalSince1970: 1_700_000_030)
            )
        ],
        skillInvocations: [SkillInvocation(skill: "demo", turnIndex: 1)],
        workspaceDiff: WorkspaceDiff(added: ["out.txt"]),
        usage: nil
    )

    /// The baseline-arm canned trace (F15): same session shape, **zero skill invocations** — what a
    /// provably skill-free run looks like.
    public static let cannedBaselineTrace = Trace(
        harness: "replay",
        harnessVersion: "replay-1",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        endedAt: Date(timeIntervalSince1970: 1_700_000_060),
        turns: [
            Turn(role: .user, text: "do it", at: Date(timeIntervalSince1970: 1_700_000_000)),
            Turn(
                role: .assistant, text: "done (no skill)",
                toolCalls: [ToolCall(name: "write", input: "out.txt")],
                filesTouched: ["out.txt"],
                at: Date(timeIntervalSince1970: 1_700_000_030)
            )
        ],
        skillInvocations: [],
        workspaceDiff: WorkspaceDiff(added: ["out.txt"]),
        usage: nil
    )
}
