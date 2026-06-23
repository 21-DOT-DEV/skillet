import Foundation
import YAML
import EDDCore

/// Decodes `skillet.yaml` into the pure `SkilletConfig` (EDDCore). This is the **only** target that
/// touches `swift-yaml` / C++ interop. The interop is viral, so direct importers of `ConfigYAML` must
/// enable C++ interop — but the kits and pure core never import it; they take a decoded `SkilletConfig`
/// as input, staying interop-free.
public enum ConfigLoader {
    /// Decode a YAML string into a `SkilletConfig`.
    public static func decode(_ yaml: String) throws -> SkilletConfig {
        try YAMLDecoder().decode(SkilletConfig.self, from: yaml)
    }

    /// Load `<root>/skillet.yaml` if present; `nil` when absent.
    public static func load(from root: URL) throws -> SkilletConfig? {
        let url = root.appendingPathComponent("skillet.yaml")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(String(contentsOf: url, encoding: .utf8))
    }
}
