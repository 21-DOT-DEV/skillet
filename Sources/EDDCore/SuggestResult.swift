import Foundation

/// The `skillet.suggest/1` machine summary (`skillet suggest --json`) — **STABLE from day one**
/// (Specs/018 §5b), unlike the drafted file it points at.
///
/// **Report-and-point.** It says what happened and names the file that was written; the file is the
/// source of truth for edit content, which is deliberately **not** duplicated here. Nesting the
/// (provisional) drafted-edit shape inside this (stable) one would make every future tweak to that shape
/// a breaking change for anyone's scripts — the cascade schema-evolution guidance exists to prevent.
///
/// Mirrors exactly the facts the human output prints — nothing speculative (the rule ``TriageReport``
/// already follows). **Compatibility promise: additive-only; consumers must ignore unrecognized fields.**
public struct SuggestResult: SchemaIdentified, Codable, Sendable, Equatable {
    public static let schema = "skillet.suggest/1"

    public let skill: String
    /// The drafted set's id — `nil` on a dry run, where nothing was drafted.
    public let proposalId: String?
    /// Project-relative path of the file written — `nil` on a dry run.
    public let path: String?
    /// How many edits the set carries (the content itself lives in the file at `path`).
    public let edits: Int
    public let motivation: [String]
    public let expected: [String]
    public let model: String
    /// Which version of the drafting instructions was used. Recorded here because a **preview** writes
    /// no file — and the drafted file is otherwise the only place this is captured, so preview would be
    /// the one case that cannot answer "based on what instructions?".
    public let promptVersion: String
    /// What the assembled prompt would cost, in bytes — printed before spending, and the value the
    /// refusing ceiling is checked against (D5).
    public let estimatedPromptBytes: Int
    public let dryRun: Bool
    /// Anything skipped or rejected, with its reason (dropped edits, collisions, refused reads).
    public let disclosures: [Disclosure]

    public init(skill: String, proposalId: String?, path: String?, edits: Int,
                motivation: [String], expected: [String], model: String, promptVersion: String,
                estimatedPromptBytes: Int, dryRun: Bool, disclosures: [Disclosure]) {
        self.skill = skill; self.proposalId = proposalId; self.path = path; self.edits = edits
        self.motivation = motivation; self.expected = expected; self.model = model
        self.promptVersion = promptVersion
        self.estimatedPromptBytes = estimatedPromptBytes; self.dryRun = dryRun
        self.disclosures = disclosures
    }

    /// Written by hand so the **key set is fixed**: Swift's synthesized encoder omits `nil` optionals,
    /// which would make `proposal_id`/`path` vanish on a dry run and force every consumer to branch on a
    /// key's existence. A stable contract is easier to script against when the shape never changes — the
    /// two nullable fields are always present, carrying `null`. Decoding stays synthesized, so it accepts
    /// `null` and an absent key alike.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(skill, forKey: .skill)
        try c.encode(proposalId, forKey: .proposalId)          // `encode`, not `encodeIfPresent` → null
        try c.encode(path, forKey: .path)
        try c.encode(edits, forKey: .edits)
        try c.encode(motivation, forKey: .motivation)
        try c.encode(expected, forKey: .expected)
        try c.encode(model, forKey: .model)
        try c.encode(promptVersion, forKey: .promptVersion)
        try c.encode(estimatedPromptBytes, forKey: .estimatedPromptBytes)
        try c.encode(dryRun, forKey: .dryRun)
        try c.encode(disclosures, forKey: .disclosures)
    }
}
