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

    /// SKILL.md is prose (≤ 500 lines by spec); evals.json can carry many cases. Past-cap reads are
    /// refused, never slurped (F33 security pass).
    static let skillMDCap = 1 << 20     // 1 MiB
    static let evalsCap = 8 << 20       // 8 MiB

    /// Read `<dir>/SKILL.md` (required) and `<dir>/evaluations/evals.json` (optional). A missing or
    /// refused `SKILL.md` is an environment error — the directory isn't a usable skill. Reads go
    /// through the safe-read helper (F33 security pass): the previous unguarded, unbounded
    /// `String(contentsOf:)` meant a FIFO named `SKILL.md` in a cloned repo hung `lint`/`doctor` forever.
    public func read(skillDirectory dir: URL) throws -> RawSkill {
        let skillMarkdown = dir.appendingPathComponent("SKILL.md")
        let markdown: String
        switch SafeFile.readPlainText(skillMarkdown, cap: Self.skillMDCap) {
        case let .success(text):
            markdown = text
        case let .failure(refusal):
            throw EDDError.skillNotVisible(
                skill: dir.lastPathComponent,
                reason: "SKILL.md \(refusal == .notFound ? "is missing" : refusal.reason) at \(skillMarkdown.path)"
            )
        }
        // Optional input: absent → nil, and a refusal (special file / link trick) also → nil — the
        // planted entry must simply never be opened; the lint catalog reports the has-evals state.
        let evalsURL = dir.appendingPathComponent("evaluations/evals.json")
        let evalsJSON: Data?
        if case let .success(data) = SafeFile.readPlainData(evalsURL, cap: Self.evalsCap) {
            evalsJSON = data
        } else {
            evalsJSON = nil
        }
        return RawSkill(
            name: dir.lastPathComponent,
            path: dir,
            markdown: markdown,
            evalsJSON: evalsJSON
        )
    }
}
