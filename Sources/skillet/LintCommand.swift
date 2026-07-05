import ArgumentParser
import Foundation
import EDDCore
import ProjectKit
import ConfigYAML
import LintKit
import RenderKit

/// `skillet lint` — free, model-free static analysis of SKILL.md source (design §6.1): the cheapest
/// gate, run before any paid harness call. Exits 1 on any error-tier finding. Exemptions come from
/// `[lint].disable` in skillet.yaml, never inline pragmas.
struct LintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Free static analysis of SKILL.md source.",
        discussion: """
        Checks each skill's SKILL.md against the stable SKILL-Lxxx catalog without calling a harness: \
        description length (L001), body budget (L003), and presence of evals (L009). Exits 1 if any \
        error-tier rule fires. Configure thresholds and exemptions under `lint:` in skillet.yaml.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Limit to specific skills by name; defaults to all discovered skills.")
    var skills: [String] = []

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
            guard let root = context.root.map({ URL(fileURLWithPath: $0) }) else {
                throw EDDError.projectNotFound(cwd: context.cwd)
            }

            let config = try loadConfig(options: options, context: context)
            let skillsRoot = config?.project?.skillsRoot ?? "skills"
            let lintConfig = config?.lint ?? .init()

            let discovered = SkillScanner().scan(skillsRoot: root.appendingPathComponent(skillsRoot))
            let selected = try selectSkillDirectories(discovered, requested: skills, command: "lint")

            let reader = SkillReader()
            var diagnostics: [Diagnostic] = []
            for directory in selected {
                let raw = try reader.read(skillDirectory: directory)
                diagnostics += Linter().lint(assembleSkillSource(raw), config: lintConfig)   // shared assembly (LintSupport)
            }
            let report = LintReport(diagnostics: diagnostics)

            Console.emit(try renderer.renderLint(report, nextSteps: Self.nextSteps()))
            // A measured failure (error-tier finding) is exit 1 — not an EDDError, which models
            // usage/environment problems. Render first, then carry the code out.
            if report.errors > 0 {
                throw SilentExit(code: ExitCode.measuredFailure.rawValue)
            }
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }

    /// Onboarding: suggest the next loop step that exists today (`run`/`next` land in later phases).
    static func nextSteps() -> [String] {
        let registered = Set(SkilletCommand.configuration.subcommands.compactMap { $0.configuration.commandName })
        let available = ["run", "next"].filter { registered.contains($0) }.map { "skillet \($0)" }
        return available.isEmpty ? ["skillet --help"] : available
    }
}
