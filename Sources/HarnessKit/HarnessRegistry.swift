import TraceKit

/// The set of registered harness adapters, surfaced by `skillet harness list`/`info`.
public struct HarnessRegistry: Sendable {
    public let adapters: [any HarnessAdapter]
    public init(adapters: [any HarnessAdapter]) { self.adapters = adapters }

    /// The default registry: the replay double + the real claude-code adapter (live `run` lands in F7).
    public static let `default` = HarnessRegistry(adapters: [ReplayAdapter(), ClaudeCodeAdapter()])

    public func adapter(id: HarnessID) -> (any HarnessAdapter)? {
        adapters.first { $0.id == id }
    }
}
