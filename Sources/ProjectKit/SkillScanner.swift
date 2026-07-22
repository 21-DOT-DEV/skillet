import Foundation

/// Discovers skills — directories containing a `SKILL.md` (design §4) — for `init` to scaffold.
public struct SkillScanner: Sendable {
    let probe: DirectoryProbe

    public init(probe: DirectoryProbe = FileSystemProbe()) {
        self.probe = probe
    }

    /// Skills found as immediate subdirectories of `skillsRoot`, sorted for deterministic output.
    public func scan(skillsRoot: URL) -> [URL] {
        // Never follow a **symlinked skills-root** (round 14): discovery runs before any per-command
        // confinement check, and a `skills -> /elsewhere` symlink would let `contentsOfDirectory`
        // enumerate directory names outside the project *on platforms where it follows dir symlinks*
        // (macOS returns [] here, but that's Foundation-version behavior, not a contract — Linux may
        // differ). Refuse it deterministically on every platform: no skills, no enumeration.
        guard !SafeFile.isSymlink(skillsRoot) else { return [] }
        return probe.subdirectories(of: skillsRoot)
            .filter { probe.exists(named: "SKILL.md", in: $0) }
            .sorted { $0.path < $1.path }
    }

    /// From explicit `--skill` paths, keep those that are skills (contain `SKILL.md`).
    public func explicit(_ paths: [URL]) -> [URL] {
        paths.filter { probe.exists(named: "SKILL.md", in: $0) }
            .sorted { $0.path < $1.path }
    }
}
