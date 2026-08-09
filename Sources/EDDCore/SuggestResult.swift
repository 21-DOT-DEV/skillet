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
    /// **What this run actually did to the file**, in one word. Without it a reader cannot tell "a new
    /// draft was created" from "one was already there", and the human summary said `written` in both
    /// cases while the line below it said nothing had been written. An explicit changed/unchanged signal
    /// is the standard for a command you can run repeatedly.
    ///
    /// **This reports the file, not a verdict on the run.** A model may legitimately reply proposing no
    /// change; that still saves a file, so this still says `written` while the command leaves a non-zero
    /// status. The field that answers "is there anything here to use?" is ``edits`` — zero means nothing
    /// was proposed, which is how structured output conventionally reports an empty result, and it is
    /// deliberately the only place that is stated. A second field repeating it would be one more thing
    /// that has to stay in agreement forever, and reading this one instead is the mistake worth naming
    /// here rather than worth adding a field to prevent.
    ///
    /// - `written` — a new draft was saved.
    /// - `refreshed` — a draft was already there; its list of tests was out of date and was updated, so
    ///   the file *was* rewritten.
    /// - `unchanged` — a draft was already there and nothing needed doing.
    /// - `not-saved` — the chosen name is held by a different draft; nothing was saved.
    /// - `previewed` — a dry run; nothing was sent and nothing written.
    /// A **fixed set**, not free text. The display used to match three of these by name and let anything
    /// else fall through to a branch that printed "written <path>" — so a value nobody had handled, or a
    /// mistyped one, reported a successful write. Naming the set means a new outcome cannot be added
    /// without the display saying what it prints, checked when the code is built rather than when someone
    /// reads the output. The words written into the machine-readable output are unchanged.
    public enum Outcome: String, Codable, Sendable, Equatable, CaseIterable {
        /// A new draft was saved.
        case written
        /// A draft was already there; its list of tests was out of date and was updated, so the file
        /// *was* rewritten.
        case refreshed
        /// A draft was already there and nothing needed doing.
        case unchanged
        /// The chosen name is held by a different draft; nothing was saved.
        case notSaved = "not-saved"
        /// A dry run; nothing was sent and nothing written.
        case previewed
    }

    public let outcome: Outcome
    /// Anything skipped or rejected, with its reason (dropped edits, collisions, refused reads).
    public let disclosures: [Disclosure]

    public init(skill: String, proposalId: String?, path: String?, edits: Int,
                motivation: [String], expected: [String], model: String, promptVersion: String,
                estimatedPromptBytes: Int, dryRun: Bool, outcome: Outcome,
                disclosures: [Disclosure]) {
        self.skill = skill; self.proposalId = proposalId; self.path = path; self.edits = edits
        self.motivation = motivation; self.expected = expected; self.model = model
        self.promptVersion = promptVersion
        self.estimatedPromptBytes = estimatedPromptBytes; self.dryRun = dryRun
        self.outcome = outcome; self.disclosures = disclosures
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
        try c.encode(outcome, forKey: .outcome)
        try c.encode(disclosures, forKey: .disclosures)
    }
}
