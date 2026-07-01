import Foundation
import EDDCore
import HarnessKit
import ProjectKit
import ConfigYAML

/// Loads `skillet.yaml` for the config-consuming commands (`lint`, `harness`, `run`). **Strict on a
/// present-but-invalid config** so no command silently falls back to paid/scan defaults when the
/// committed config is broken — a config that *exists* but can't be decoded is an artifact problem,
/// not "no config":
///   - no `skillet.yaml` discovered → `nil` (defaults);
///   - explicit `--config` missing/unreadable → usage error;
///   - explicit `--config` undecodable, or a discovered repo `skillet.yaml` present-but-undecodable → artifact error.
/// (Full precedence + `config list --origins` land in Phase 2's `doctor`/config work.)
func loadConfig(options: GlobalOptions) throws -> SkilletConfig? {
    if let explicit = options.config {
        guard let text = try? String(contentsOfFile: explicit, encoding: .utf8) else {
            throw EDDError.usage(message: "config file not found or unreadable: \(explicit)",
                                 remedy: "pass --config with a readable skillet.yaml path, or omit it")
        }
        do { return try ConfigLoader.decode(text) }
        catch { throw EDDError.invalidArtifact(path: explicit, reason: "not valid skillet.yaml") }
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    // Validate `-C` the way root/lint/run do: an invalid directory is an environment error (exit 3), not
    // silently ignored (previously `try?` swallowed it → `harness list/info` ran with defaults). Discovery
    // succeeding with no project marker still yields `nil` (built-in defaults).
    let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
    guard let root = context.root else { return nil }
    // `load` returns nil when absent (→ defaults) and throws when present-but-undecodable (→ fail loud).
    do { return try ConfigLoader.load(from: URL(fileURLWithPath: root)) }
    catch { throw EDDError.invalidArtifact(path: "skillet.yaml", reason: "not valid skillet.yaml") }
}

/// The harness registry with the claude-code adapter wired to the config's resolution link. Throws if
/// the config is present-but-invalid (so `harness info` can't probe `PATH` and report a misleading
/// setup while a broken `harness.claude-code.path` is silently ignored).
func configuredRegistry(options: GlobalOptions) throws -> HarnessRegistry {
    let claudePath = try loadConfig(options: options)?.harness?.claudeCode?.path
    return HarnessRegistry(adapters: [ReplayAdapter(), ClaudeCodeAdapter(configPath: claudePath)])
}
