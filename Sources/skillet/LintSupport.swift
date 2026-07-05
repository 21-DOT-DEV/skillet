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
/// `run` uses this as its pre-spend gate; `lint` and `doctor` use it per selected skill.
func lintSkillDirectory(_ dir: URL, config: SkilletConfig.Lint) throws -> LintReport {
    let raw = try SkillReader().read(skillDirectory: dir)
    return LintReport(diagnostics: Linter().lint(assembleSkillSource(raw), config: config))
}

/// Resolve requested skill **names** to discovered directories, de-duplicated and sorted for
/// deterministic output — shared by `lint` and `doctor` so selection semantics can't drift. Skills
/// are uniquely named under `skills_root`, so selection is by name — not path — which is `-C`/cwd-
/// independent; an unknown name is a usage error that lists what's available. With no request, the
/// discovered set passes through in scan order — already sorted (`SkillScanner.scan` sorts for
/// deterministic output), so callers need no re-sort.
func selectSkillDirectories(_ discovered: [URL], requested: [String], command: String) throws -> [URL] {
    guard !requested.isEmpty else { return discovered }
    let byName = Dictionary(discovered.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
    let matched = try requested.map { name -> URL in
        guard let match = byName[name] else {
            let available = discovered.map(\.lastPathComponent).sorted()
            throw EDDError.usage(
                message: "unknown skill: \(name)",
                remedy: available.isEmpty
                    ? "no skills found under skills_root; run `skillet \(command)` with no arguments"
                    : "choose one of: \(available.joined(separator: ", ")), or run `skillet \(command)` with no arguments"
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
