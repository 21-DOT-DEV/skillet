import Foundation
import EDDCore
import HarnessKit
import ProjectKit
import ConfigYAML

/// Where the effective config came from — `doctor` (F3) reports the *file* origin; the per-value
/// origins table (`config list --origins`) is F24.
enum ConfigOrigin: Equatable {
    case explicit(path: String)
    case repo(path: String)
    case defaults

    var human: String {
        switch self {
        case let .explicit(path): "loaded \(path) (--config)"
        case let .repo(path): "loaded \(path)"
        case .defaults: "no skillet.yaml — built-in defaults"
        }
    }
}

/// Loads `skillet.yaml` for the config-consuming commands (`lint`, `harness`, `run`, `doctor`).
/// **Strict on a present-but-invalid config** so no command silently falls back to paid/scan defaults
/// when the committed config is broken — a config that *exists* but can't be decoded is an artifact
/// problem, not "no config":
///   - no `skillet.yaml` discovered → `nil` (defaults);
///   - explicit `--config` missing/unreadable → usage error;
///   - explicit `--config` undecodable, or a discovered repo `skillet.yaml` present-but-undecodable → artifact error.
/// (Full precedence + `config list --origins` land with F24; `doctor` reports the file origin.)
/// A caller that has already located the project passes its `context` so the project is located
/// exactly once per invocation (and `-C` handling can never diverge between the two).
func loadConfigWithOrigin(options: GlobalOptions, context: ProjectContext? = nil) throws -> (config: SkilletConfig?, origin: ConfigOrigin) {
    if let explicit = options.config {
        guard let text = try? String(contentsOfFile: explicit, encoding: .utf8) else {
            throw EDDError.usage(message: "config file not found or unreadable: \(explicit)",
                                 remedy: "pass --config with a readable skillet.yaml path, or omit it")
        }
        do { return (try ConfigLoader.decode(text), .explicit(path: explicit)) }
        catch { throw EDDError.invalidArtifact(path: explicit, reason: "not valid skillet.yaml") }
    }
    // Validate `-C` the way root/lint/run do: an invalid directory is an environment error (exit 3), not
    // silently ignored (previously `try?` swallowed it → `harness list/info` ran with defaults). Discovery
    // succeeding with no project marker still yields `nil` (built-in defaults).
    let located: ProjectContext
    if let context {
        located = context
    } else {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        located = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
    }
    guard let root = located.root else { return (nil, .defaults) }
    // `load` returns nil when absent (→ defaults) and throws when present-but-undecodable (→ fail loud).
    do {
        let config = try ConfigLoader.load(from: URL(fileURLWithPath: root))
        return (config, config == nil ? .defaults : .repo(path: root + "/skillet.yaml"))
    }
    catch { throw EDDError.invalidArtifact(path: "skillet.yaml", reason: "not valid skillet.yaml") }
}

/// The config without its origin — the pre-F3 surface most commands use.
func loadConfig(options: GlobalOptions, context: ProjectContext? = nil) throws -> SkilletConfig? {
    try loadConfigWithOrigin(options: options, context: context).config
}

/// The harness registry with the claude-code adapter wired to the config's resolution link. Throws if
/// the config is present-but-invalid (so `harness info` can't probe `PATH` and report a misleading
/// setup while a broken `harness.claude-code.path` is silently ignored).
func configuredRegistry(options: GlobalOptions) throws -> HarnessRegistry {
    let claudePath = try loadConfig(options: options)?.harness?.claudeCode?.path
    return HarnessRegistry(adapters: [ReplayAdapter(), ClaudeCodeAdapter(configPath: claudePath)])
}
