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
            // **A skill folder that is a link is not walked into.** Only the folder holding the skills
            // was refused, not an individual skill inside it — so a link there pointing anywhere on the
            // machine was read and reported on by the commands that only inspect a skill, while the
            // commands that run or edit one refused it. Two halves of the tool disagreeing about what
            // counts as a skill.
            //
            // Declining is what every tool that walks directories for a living does by default —
            // measured: `find`, `ripgrep` and `git` all leave them alone unless asked otherwise, because
            // following invites loops and surprises. What is skipped is reported by the caller, which is
            // where this parts company with those tools on purpose: a skill is a named thing someone
            // expects to see checked, not one file among thousands, so dropping one in silence would
            // mean believing you had checked everything.
            .filter { !SafeFile.isSymlink($0) }
            .filter { probe.exists(named: "SKILL.md", in: $0) }
            .sorted { $0.path < $1.path }
    }

    /// From explicit `--skill` paths, keep those that are skills (contain `SKILL.md`).
    public func explicit(_ paths: [URL]) -> [URL] {
        paths.filter { probe.exists(named: "SKILL.md", in: $0) }
            .sorted { $0.path < $1.path }
    }
}
