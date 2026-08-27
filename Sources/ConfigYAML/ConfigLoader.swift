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

    // NOTE (F33 security pass): the file-reading `load(from:)` was removed — it read the settings file
    // unguarded and without a limit, so a settings file that was really a device or a pipe, or simply
    // enormous, was handed straight to the decoder. The sole caller
    // (`ConfigSupport.loadConfigWithOrigin`) now reads via `SafeFile.readPlainText`, which checks the
    // path is an ordinary file before opening it and bounds what it reads; this seam stays pure text →
    // `SkilletConfig`.
    //
    // **Corrected 2026-08-19.** This note used to say the hang came from `String(contentsOf:)`. Measured,
    // it does not: against a named pipe with a writer attached, `String(contentsOf:)`, `Data(contentsOf:)`
    // and `FileManager.contents(atPath:)` all refuse instantly, while `FileHandle.readDataToEndOfFile()`
    // blocks indefinitely. The hazard is real and the guard is right — the attribution was wrong, and it
    // is stated correctly in `WorkspaceManager.swift:296` and `CorpusLoader.swift:38`. The rule the guard
    // actually implements is CERT FIO32-C: do not perform file operations on something that may not be an
    // ordinary file, because a name from an untrusted source can point at a device or a pipe.
}
