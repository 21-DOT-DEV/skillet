import EDDCore

/// The pure input to the linter: a single skill's already-parsed source. Assembling this — reading
/// files, parsing YAML frontmatter, decoding `evals.json` — happens in the executable, so `LintKit`
/// itself stays free of I/O and YAML/C++ interop (the load-bearing layering choice, design §11).
public struct SkillSource: Sendable, Equatable {
    /// The skill's directory name — its id in diagnostics.
    public let name: String
    /// The decoded frontmatter, or `nil` when it was missing/unparseable — which `SKILL-L001` reports.
    public let frontmatter: SkillFrontmatter?
    /// The `SKILL.md` body, with the frontmatter block already stripped.
    public let body: String
    /// The skill's `evals.json`, or `nil` when absent **or unparseable** — which `SKILL-L009` reports.
    public let evals: EvalsFile?
    /// Whether an `evals.json` file existed at all (regardless of whether it parsed), so `SKILL-L009`
    /// can tell "missing" from "present but invalid".
    public let evalsPresent: Bool

    public init(name: String, frontmatter: SkillFrontmatter?, body: String, evals: EvalsFile?, evalsPresent: Bool) {
        self.name = name
        self.frontmatter = frontmatter
        self.body = body
        self.evals = evals
        self.evalsPresent = evalsPresent
    }
}
