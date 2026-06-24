import EDDCore
import TraceKit

/// The `--json` payload for `skillet harness info` / `list` (`skillet.harness-info/1`): each adapter
/// with its id, capability names, and probe status.
public struct HarnessInfoReport: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.harness-info/1"
    public let adapters: [AdapterInfo]
    public init(adapters: [AdapterInfo]) { self.adapters = adapters }

    public struct AdapterInfo: Codable, Sendable, Equatable {
        public let id: String
        public let capabilities: [String]
        public let available: Bool
        public let version: String?
        public let detail: String?
        public let warnings: [String]
        public init(id: String, capabilities: [String], available: Bool, version: String?, detail: String?, warnings: [String] = []) {
            self.id = id
            self.capabilities = capabilities
            self.available = available
            self.version = version
            self.detail = detail
            self.warnings = warnings
        }
    }

    /// Probe every adapter (catching errors — `harness info` is informational and never fails) and
    /// assemble the report.
    public static func build(from registry: HarnessRegistry) async -> HarnessInfoReport {
        var infos: [AdapterInfo] = []
        for adapter in registry.adapters {
            let capabilities = adapter.capabilities.names
            do {
                let info = try await adapter.probe()
                infos.append(AdapterInfo(
                    id: adapter.id.rawValue,
                    capabilities: capabilities,
                    available: info.available,
                    version: info.version,
                    detail: info.authenticated ? nil : "not authenticated",
                    warnings: info.warnings
                ))
            } catch HarnessError.notImplemented(let message) {
                infos.append(AdapterInfo(id: adapter.id.rawValue, capabilities: capabilities, available: false, version: nil, detail: message))
            } catch let error as EDDError {
                // Surface the human "what + why", not the raw enum case.
                infos.append(AdapterInfo(id: adapter.id.rawValue, capabilities: capabilities, available: false, version: nil, detail: error.message))
            } catch {
                infos.append(AdapterInfo(id: adapter.id.rawValue, capabilities: capabilities, available: false, version: nil, detail: "\(error)"))
            }
        }
        return HarnessInfoReport(adapters: infos)
    }
}
