import Foundation
import EDDCore

/// The raw, on-disk material for one skill — the I/O half of assembling a lint `SkillSource`. Parsing
/// (frontmatter split, `evals.json` decode) happens in the executable, so `ProjectKit` stays free of
/// YAML/JSON concerns.
public struct RawSkill: Sendable, Equatable {
    /// The skill directory's name — its id in diagnostics.
    public let name: String
    /// The skill directory.
    public let path: URL
    /// The `SKILL.md` text.
    public let markdown: String
    /// The `evaluations/evals.json` bytes, or `nil` when the file is absent.
    public let evalsJSON: Data?

    public init(name: String, path: URL, markdown: String, evalsJSON: Data?) {
        self.name = name
        self.path = path
        self.markdown = markdown
        self.evalsJSON = evalsJSON
    }
}

/// Reads a skill directory's lint inputs from disk (design §11 — the effectful kit over the pure core).
public struct SkillReader: Sendable {
    public init() {}

    /// Read `<dir>/SKILL.md` (required) and `<dir>/evaluations/evals.json` (optional). A missing or
    /// unreadable `SKILL.md` is an environment error — the directory isn't a usable skill.
    public func read(skillDirectory dir: URL) throws -> RawSkill {
        let skillMarkdown = dir.appendingPathComponent("SKILL.md")
        guard let markdown = try? String(contentsOf: skillMarkdown, encoding: .utf8) else {
            throw EDDError.skillNotVisible(
                skill: dir.lastPathComponent,
                reason: "SKILL.md is missing or unreadable at \(skillMarkdown.path)"
            )
        }
        let evalsURL = dir.appendingPathComponent("evaluations/evals.json")
        return RawSkill(
            name: dir.lastPathComponent,
            path: dir,
            markdown: markdown,
            evalsJSON: try? Data(contentsOf: evalsURL)
        )
    }
}
