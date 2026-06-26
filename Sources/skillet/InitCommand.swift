import ArgumentParser
import Foundation
import EDDCore
import ProjectKit
import RenderKit

/// `skillet init` — adopt skillet in a repository (design §6.1). Writes a commented `skillet.yaml`,
/// scaffolds each skill's `evaluations/` evidence directories, and keeps the `.skillet/` cache out
/// of git. Idempotent. (User-facing description lives in `abstract`/`discussion`/`help:`, not here.)
struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Adopt skillet in a repository.",
        discussion: """
        Writes a commented skillet.yaml, scaffolds each skill's evaluations/ evidence directories, \
        and keeps the .skillet/ cache out of git via a self-owned .skillet/.gitignore. Idempotent: \
        re-running fills gaps and never overwrites.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Scaffold a specific skill directory (repeatable); defaults to discovery under skills_root.")
    var skill: [String] = []

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            // init sets up the project *here* (cwd or -C); it does not walk up to a git boundary.
            let root = try ProjectLocator().resolveStart(dashC: options.directory, cwd: cwd)
            let skillsRoot = "skills" // default; custom skills_root honoring arrives with config parsing

            let scanner = SkillScanner()
            let skills: [URL]
            if skill.isEmpty {
                skills = scanner.scan(skillsRoot: root.appendingPathComponent(skillsRoot))
            } else {
                skills = scanner.explicit(try resolveSkillPaths(skill, cwd: cwd))
            }

            let plan = InitPlanner().plan(root: root, skillsRoot: skillsRoot, skills: skills)
            let report = try InitExecutor().apply(plan, root: root)
            Console.emit(try renderer.renderInit(report, nextSteps: Self.nextSteps(skillsFound: !report.skills.isEmpty)))
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }

    /// Resolve explicit `--skill` paths against the cwd; a missing/unreadable path is exit 3.
    private func resolveSkillPaths(_ paths: [String], cwd: URL) throws -> [URL] {
        let base = URL(fileURLWithPath: cwd.path, isDirectory: true)
        return try paths.map { raw in
            let url = URL(fileURLWithPath: raw, relativeTo: base).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw EDDError.directoryNotFound(path: url.path)
            }
            return url
        }
    }

    /// Onboarding commands to suggest — the canonical loop order, filtered to commands that exist
    /// today (never advertises an unimplemented command). Grows automatically as features register.
    static func nextSteps(skillsFound: Bool) -> [String] {
        let registered = Set(SkilletCommand.configuration.subcommands.compactMap { $0.configuration.commandName })
        let available = ["lint", "doctor", "run", "next"].filter { registered.contains($0) }.map { "skillet \($0)" }
        if !available.isEmpty { return available }
        return skillsFound ? ["skillet --help"] : ["add a SKILL.md under skills/, then re-run skillet init"]
    }
}
