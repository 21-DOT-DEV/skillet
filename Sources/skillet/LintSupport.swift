import Foundation
import EDDCore
import ProjectKit
import ConfigYAML
import LintKit

/// Shared lint-input assembly used by **both** `skillet lint` and `run`'s free lint preflight — factored
/// here so the two can't drift (design constitution V: free-before-paid, one gate definition).

/// Assemble a pure ``SkillSource`` from a skill directory's raw bytes: parse the frontmatter (`nil` when
/// unparseable, which L001 reports) and decode `evals.json` (`nil` when absent/corrupt, which L009
/// reports). No I/O — the reading half is ``SkillReader``.
func assembleSkillSource(_ raw: RawSkill) -> SkillSource {
    let parsed = try? FrontmatterParser.parse(raw.markdown)
    let evals = raw.evalsJSON.flatMap { try? JSONDecoder().decode(EvalsFile.self, from: $0) }
    return SkillSource(
        name: raw.name,
        frontmatter: parsed?.frontmatter,
        // On a frontmatter parse failure L001 already errors; feed an empty body so L003 doesn't also
        // fire on the (unsplit) frontmatter lines.
        body: parsed?.body ?? "",
        evals: evals,
        evalsPresent: raw.evalsJSON != nil
    )
}

/// Read + assemble + lint one skill directory (the free error-tier catalog, honoring `lint.disable`).
/// `run` uses this as its pre-spend gate; `lint` uses it per selected skill.
func lintSkillDirectory(_ dir: URL, config: SkilletConfig.Lint) throws -> LintReport {
    let raw = try SkillReader().read(skillDirectory: dir)
    return LintReport(diagnostics: Linter().lint(assembleSkillSource(raw), config: config))
}
