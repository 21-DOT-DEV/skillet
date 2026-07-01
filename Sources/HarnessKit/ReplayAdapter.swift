import Foundation
import TraceKit

/// An in-memory `HarnessAdapter` for tests — and the proof that the seam is implementable
/// end-to-end with no live harness. Serves a deterministic synthetic `Trace`.
public struct ReplayAdapter: HarnessAdapter {
    public let id: HarnessID = "replay"
    public let capabilities: HarnessCapabilities = [.runTask, .skillInjection, .traceParsing]
    public init() {}

    public func probe(strict: Bool) async throws -> HarnessInfo {
        HarnessInfo(id: id, version: "replay-1", authenticated: true, available: true)
    }

    public func verifySkillVisibility(_ skill: SkillRef, strategy: InjectionStrategy) throws {
        // The replay double "sees" everything — visibility always holds.
    }

    public func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
        RawTrace(harness: id, raw: "replayed: \(task.query)")
    }

    public func parseTrace(_ raw: RawTrace) throws -> Trace {
        Self.cannedTrace
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
}
