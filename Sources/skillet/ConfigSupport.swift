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
/// Config files are small; anything past this is refused, not read (F33 security pass).
private let configReadCap = 1 << 20   // 1 MiB

func loadConfigWithOrigin(options: GlobalOptions, context: ProjectContext? = nil) throws -> (config: SkilletConfig?, origin: ConfigOrigin) {
    if let explicit = options.config {
        // Safe read (F33 security pass): an operator-supplied path is untrusted input — a FIFO here
        // previously hung every config-consuming command via an unbounded `String(contentsOfFile:)`.
        let text: String
        switch SafeFile.readPlainText(URL(fileURLWithPath: explicit), cap: configReadCap) {
        case let .success(contents):
            text = contents
        case let .failure(refusal):
            throw EDDError.usage(message: "config file \(refusal.reason): \(explicit)",
                                 remedy: "pass --config with a plain readable skillet.yaml path, or omit it")
        }
        do { return (try validated(ConfigLoader.decode(text), path: explicit), .explicit(path: explicit)) }
        catch let error as EDDError { throw error }
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
    // Safe read (F33 security pass): a cloned repo's `skillet.yaml` is untrusted — a FIFO here
    // previously hung EVERY command at config load (the read was an unguarded, unbounded
    // `String(contentsOf:)` behind a bare exists-check). Absent stays defaults; a refusal (symlink /
    // special file / hard link / oversized / binary) fails loud as an artifact error, exactly like
    // present-but-undecodable — a config that exists but can't be *safely* read is an artifact problem.
    let url = URL(fileURLWithPath: root).appendingPathComponent("skillet.yaml")
    switch SafeFile.readPlainText(url, cap: configReadCap) {
    case .failure(.notFound):
        return (nil, .defaults)
    case let .failure(refusal):
        throw EDDError.invalidArtifact(path: "skillet.yaml", reason: "skillet.yaml \(refusal.reason)")
    case let .success(text):
        do { return (try validated(ConfigLoader.decode(text), path: "skillet.yaml"), .repo(path: root + "/skillet.yaml")) }
        catch let error as EDDError { throw error }
        catch { throw EDDError.invalidArtifact(path: "skillet.yaml", reason: "not valid skillet.yaml") }
    }
}

/// Value-level validation at the trust boundary (F33 security pass): every command reads config through
/// this seam, so an **accept-known-good** check here covers lint/doctor/run/triage at once — the
/// comprehensive-fix stance (patch the class, not the reported path). Deeper per-command confinement
/// guards stay as layered defense. Today's one rule: `skills_root` must be a plain relative subpath.
private func validated(_ config: SkilletConfig, path: String) throws -> SkilletConfig {
    if let skillsRoot = config.project?.skillsRoot,
       let violation = SkilletConfig.Project.skillsRootViolation(skillsRoot) {
        throw EDDError.invalidArtifact(
            path: path,
            reason: "project.skills_root '\(skillsRoot)' \(violation) — it must name a folder inside the project (a plain relative subpath)")
    }
    return config
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
