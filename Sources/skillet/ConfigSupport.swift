import Foundation
import EDDCore
import HarnessKit
import ProjectKit
import ConfigYAML

/// Loads `skillet.yaml` (best-effort) so the harness resolution chain can honor its config link
/// (F6 the first consumer). Full precedence, `config list --origins`, and loud config errors land in
/// F3; F6 reads only the slice the resolver needs and treats absence/parse failure as "no config".
func loadConfig(options: GlobalOptions) -> SkilletConfig? {
    if let explicit = options.config {
        return try? ConfigLoader.decode(String(contentsOfFile: explicit, encoding: .utf8))
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    guard let context = try? ProjectLocator().locate(dashC: options.directory, cwd: cwd),
          let root = context.root else { return nil }
    return try? ConfigLoader.load(from: URL(fileURLWithPath: root))
}

/// The harness registry with the claude-code adapter wired to the config's resolution link.
func configuredRegistry(options: GlobalOptions) -> HarnessRegistry {
    let claudePath = loadConfig(options: options)?.harness?.claudeCode?.path
    return HarnessRegistry(adapters: [ReplayAdapter(), ClaudeCodeAdapter(configPath: claudePath)])
}
