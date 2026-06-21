import TraceKit

/// The set of registered harness adapters, surfaced by `skillet harness list`/`info`.
public struct HarnessRegistry: Sendable {
    public let adapters: [any HarnessAdapter]
    public init(adapters: [any HarnessAdapter]) { self.adapters = adapters }

    /// The default registry: the replay double + the claude-code stub (real probe/run land in F6).
    public static let `default` = HarnessRegistry(adapters: [HarnessReplay(), ClaudeCodeAdapter()])

    public func adapter(id: HarnessID) -> (any HarnessAdapter)? {
        adapters.first { $0.id == id }
    }
}
