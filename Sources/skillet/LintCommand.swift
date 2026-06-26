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

            let config = loadConfig(options: options)
            let skillsRoot = config?.project?.skillsRoot ?? "skills"
            let lintConfig = config?.lint ?? .init()

            let discovered = SkillScanner().scan(skillsRoot: root.appendingPathComponent(skillsRoot))
            let selected = try select(discovered, requested: skills)

            let linter = Linter()
            let reader = SkillReader()
            var diagnostics: [Diagnostic] = []
            for directory in selected {
                let raw = try reader.read(skillDirectory: directory)
                diagnostics += linter.lint(assemble(raw), config: lintConfig)
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

    /// Assemble a pure `SkillSource` from raw bytes: parse the frontmatter (`nil` when unparseable,
    /// which L001 reports) and decode `evals.json` (`nil` when absent/corrupt, which L009 reports).
    private func assemble(_ raw: RawSkill) -> SkillSource {
        let parsed = try? FrontmatterParser.parse(raw.markdown)
        let evals = raw.evalsJSON.flatMap { try? JSONDecoder().decode(EvalsFile.self, from: $0) }
        return SkillSource(
            name: raw.name,
            frontmatter: parsed?.frontmatter,
            // On a frontmatter parse failure L001 already errors; feed an empty body so L003 doesn't
            // also fire on the (unsplit) frontmatter lines.
            body: parsed?.body ?? "",
            evals: evals,
            evalsPresent: raw.evalsJSON != nil
        )
    }

    /// Resolve requested skill **names** to discovered directories, de-duplicated and sorted for
    /// deterministic output. Skills are uniquely named under `skills_root`, so selection is by name —
    /// not path — which is `-C`/cwd-independent; an unknown name is a usage error that lists what's
    /// available. (Path-based selection can be added later if an out-of-tree use case appears.)
    private func select(_ discovered: [URL], requested: [String]) throws -> [URL] {
        guard !requested.isEmpty else { return discovered }
        let byName = Dictionary(discovered.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        let matched = try requested.map { name -> URL in
            guard let match = byName[name] else {
                let available = discovered.map(\.lastPathComponent).sorted()
                throw EDDError.usage(
                    message: "unknown skill: \(name)",
                    remedy: available.isEmpty
                        ? "no skills found under skills_root; run `skillet lint` with no arguments"
                        : "choose one of: \(available.joined(separator: ", ")), or run `skillet lint` with no arguments"
                )
            }
            return match
        }
        // De-duplicate repeated names and sort, so output order never depends on how names were listed.
        var seen = Set<String>()
        return matched
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Onboarding: suggest the next loop step that exists today (`run`/`next` land in later phases).
    static func nextSteps() -> [String] {
        let registered = Set(SkilletCommand.configuration.subcommands.compactMap { $0.configuration.commandName })
        let available = ["run", "next"].filter { registered.contains($0) }.map { "skillet \($0)" }
        return available.isEmpty ? ["skillet --help"] : available
    }
}
