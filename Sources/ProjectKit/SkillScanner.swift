import Foundation

/// Discovers skills — directories containing a `SKILL.md` (design §4) — for `init` to scaffold.
public struct SkillScanner: Sendable {
    let probe: DirectoryProbe

    public init(probe: DirectoryProbe = FileSystemProbe()) {
        self.probe = probe
    }

    /// Skills found as immediate subdirectories of `skillsRoot`, sorted for deterministic output.
    public func scan(skillsRoot: URL) -> [URL] {
        probe.subdirectories(of: skillsRoot)
            .filter { probe.exists(named: "SKILL.md", in: $0) }
            .sorted { $0.path < $1.path }
    }

    /// From explicit `--skill` paths, keep those that are skills (contain `SKILL.md`).
    public func explicit(_ paths: [URL]) -> [URL] {
        paths.filter { probe.exists(named: "SKILL.md", in: $0) }
            .sorted { $0.path < $1.path }
    }
}
