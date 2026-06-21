import TraceKit

/// Declared stub for the claude-code harness. Capabilities are known; every effectful method throws
/// `.notImplemented` until **F6** lands the real probe/run/parser. Enough for `harness info` to list
/// it honestly today.
public struct ClaudeCodeAdapter: HarnessAdapter {
    public let id: HarnessID = "claude-code"
    public let capabilities: HarnessCapabilities = [.runTask, .skillInjection, .traceParsing, .sessionCapture]
    public init() {}

    private func unimplemented() -> HarnessError { .notImplemented("claude-code adapter arrives in F6") }

    public func probe() async throws -> HarnessInfo { throw unimplemented() }
    public func verifySkillVisibility(_ skill: SkillRef, strategy: InjectionStrategy) throws { throw unimplemented() }
    public func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace { throw unimplemented() }
    public func parseTrace(_ raw: RawTrace) throws -> Trace { throw unimplemented() }
    public func locateSessions(_ query: SessionQuery) async throws -> [NativeSessionRef] { throw unimplemented() }
    public func exportSession(_ ref: NativeSessionRef) async throws -> RawTrace { throw unimplemented() }
}
