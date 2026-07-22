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

    // NOTE (F33 security pass): the file-reading `load(from:)` was removed — its unguarded, unbounded
    // `String(contentsOf:)` let a FIFO named `skillet.yaml` hang every command at config load. The sole
    // caller (`ConfigSupport.loadConfigWithOrigin`) now reads via `SafeFile.readPlainText` and feeds
    // `decode`; this seam stays pure text → `SkilletConfig`.
}
