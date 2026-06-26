/// A skill's `SKILL.md` YAML frontmatter as a **pure** model (design §6.1). Decoded by the isolated
/// `ConfigYAML` target — which folds block/folded scalars — so this type stays interop-free. F4 reads
/// only `description` (for `SKILL-L001`); full key-level conformance — `name` kebab/length,
/// allowed-keys, duplicate-key rejection — lands in F3 `doctor`. Unmodeled keys are ignored on decode,
/// so new frontmatter keys never break the parse (forward-compatible).
public struct SkillFrontmatter: Codable, Sendable, Equatable {
    public var name: String?
    public var description: String?

    public init(name: String? = nil, description: String? = nil) {
        self.name = name
        self.description = description
    }
}
