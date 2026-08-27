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

/// The config file's **text**, resolved once with the precedence below, or `nil` when there is no file.
/// Every caller resolves the file through this one function, so they cannot disagree about which file
/// is in play, the precedence that chose it, or how an unreadable one is reported. (For a while a second
/// caller kept its own copy of this logic while a comment claimed otherwise; that caller — a separate
/// read of the `suggest:` section — has since been removed entirely.)
private func configText(options: GlobalOptions, context: ProjectContext?) throws
    -> (text: String, origin: ConfigOrigin, errorPath: String)? {
    if let explicit = options.config {
        switch SafeFile.readPlainText(URL(fileURLWithPath: explicit), cap: configReadCap) {
        case let .success(contents):
            return (contents, .explicit(path: explicit), explicit)
        case let .failure(refusal):
            throw EDDError.usage(message: "config file \(refusal.reason): \(explicit)",
                                 remedy: "pass --config with a plain readable skillet.yaml path, or omit it")
        }
    }
    let located: ProjectContext
    if let context {
        located = context
    } else {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        located = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
    }
    guard let root = located.root else { return nil }
    let url = URL(fileURLWithPath: root).appendingPathComponent("skillet.yaml")
    switch SafeFile.readPlainText(url, cap: configReadCap) {
    case .failure(.notFound):
        return nil
    case let .failure(refusal):
        throw refusal.rejection(path: "skillet.yaml", saying: "skillet.yaml ")
    case let .success(text):
        return (text, .repo(path: root + "/skillet.yaml"), "skillet.yaml")
    }
}

func loadConfigWithOrigin(options: GlobalOptions, context: ProjectContext? = nil) throws -> (config: SkilletConfig?, origin: ConfigOrigin) {
    // Reads through the shared resolver above — which is now true, not merely claimed. It previously
    // kept its own copy of the same read-and-branch logic, so the comment promising the two could not
    // disagree described a structure that did not exist. One reader, one precedence, one place a
    // refusal is classified; this function is only decode + validate on top.
    guard let resolved = try configText(options: options, context: context) else { return (nil, .defaults) }
    do { return (try validated(ConfigLoader.decode(resolved.text), path: resolved.errorPath), resolved.origin) }
    catch let error as EDDError { throw error }
    // Carry the decoder's detail: it names the offending key and what was wrong with it. The bare
    // "not valid skillet.yaml" told you a file you can see is broken without saying which of its eight
    // sections broke it. Consistent with every other decode failure here, which all quote the cause.
    catch { throw EDDError.invalidArtifact(path: resolved.errorPath, reason: "not valid skillet.yaml — \(DecodeFailure.describe(error))") }
}

/// Value-level validation at the trust boundary (F33 security pass): every command reads config through
/// this seam, so an **accept-known-good** check here covers lint/doctor/run/triage at once — the
/// comprehensive-fix stance (patch the class, not the reported path). Deeper per-command confinement
/// guards stay as layered defense. Today's one rule: `skills_root` must be a plain relative subpath.
private func validated(_ config: SkilletConfig, path: String) throws -> SkilletConfig {
    var config = config
    // **Canonicalize first, then judge the canonical form.** `skills_root` is pasted into user-facing
    // hints ("review findings under <skills-root>/<skill>/…"), and a legal trailing slash produced a
    // doubled separator — a copy-paste path that doesn't match the real one (path *building* hides this,
    // because `appendingPathComponent` normalizes). Doing it here, once at the trust boundary, fixes every
    // consumer at once instead of leaving a trap for the next message someone writes — the standing
    // canonicalization rule: normalize where input enters, **before** validation, never per use site
    // (CERT "Input Validation and Data Sanitization").
    //
    // Leading `/` is preserved deliberately: it is what marks the value absolute, and the check below
    // must still see it. Collapsing it away would turn `/etc/` into a *relative*-looking `etc` and let a
    // hostile config escape the project — the exact rule S7 exists to enforce.
    if let raw = config.project?.skillsRoot {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAbsolute = trimmed.hasPrefix("/")
        // Drop no-op `.` segments (`./skills` → `skills`) — the same doubled-text defect in another
        // costume. `..` is deliberately NOT dropped: the escape rule below must still see it.
        // Trim **each segment**, not just the ends: `skills /` keeps its space through a whole-value
        // trim (the trailing character is the slash), so the hint printed `skills /demo/…` and the
        // directory created carried the space — the same broken-copy-paste defect in another costume.
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." }
        var canonical = segments.joined(separator: "/")
        if isAbsolute { canonical = "/" + canonical }
        // A lone `.` is the ecosystem's conventional "the directory holding this config" (TypeScript's
        // `rootDir: "."` and friends) — a *deliberate* value, unlike a blank one, which means unset or
        // mistyped. Keep it rather than collapsing to "" (which the empty rule would then reject):
        // silently turning a working, conventional value into an error is a breaking change that would
        // deserve a deprecation period, not a bug-fix round.
        if canonical.isEmpty, !trimmed.isEmpty, !isAbsolute { canonical = "." }
        config.project?.skillsRoot = canonical
    }
    if let skillsRoot = config.project?.skillsRoot,
       let violation = SkilletConfig.Project.skillsRootViolation(skillsRoot) {
        throw EDDError.invalidArtifact(
            path: path,
            reason: "project.skills_root '\(skillsRoot)' \(violation) — it must name a folder inside the project (a plain relative subpath)",
            fix: "set project.skills_root in skillet.yaml to a folder inside the project, written as a relative path")
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

/// A project-relative path to **show a person**, assembled from the setting naming where skills live
/// plus the parts beneath it.
///
/// That setting may be the conventional `"."`, meaning skills sit at the project root. Joining it by
/// hand yields `./demo/SKILL.md` — a valid path, but not the canonical form, which is conventionally
/// written without `./` parts. One command stripped it and four did not, so the same project printed
/// two spellings of the same path depending on which command you happened to run.
///
/// Only `.` and empty parts are dropped. The settings boundary already refuses `..` and absolute values
/// and trims each part, so nothing else is left to tidy. This is for **display only** — paths used to
/// actually reach files are built separately, and a `.` in those is resolved by the operating system.
func projectRelativePath(_ segments: String...) -> String {
    segments.filter { $0 != "." && !$0.isEmpty }.joined(separator: "/")
}
