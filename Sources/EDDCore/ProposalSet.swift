import Foundation

/// The `skillet.proposal/1` drafted-edit set — the output of `skillet suggest` and (once F42/F43 land)
/// the input of apply/iterate. Written to `.skillet/proposals/<id>.json`.
///
/// **PROVISIONAL, deliberately (Specs/018 D4).** Versioned and golden-tested from day one, but *not*
/// promised stable: its readers do not exist yet, and every other frozen format here froze alongside the
/// reader that consumed it. Graduation trigger: F42 reads it back.
///
/// **Codec note (Specs/018 §5a).** Conforms to ``SchemaIdentified`` and declares **no** `schema` field of
/// its own — ``Envelope`` stamps `schema` and then merges these fields into the same object, so a payload
/// that also encoded `schema` would emit the key twice (last-wins, silently clobbering one value). A
/// hand-authored file that *does* spell out `schema` still decodes: the decoder ignores unmodeled keys.
public struct ProposalSet: SchemaIdentified, Codable, Sendable, Equatable {
    public static let schema = "skillet.proposal/1"

    /// `<run-date>-<skill>-<fingerprint>` (D7/A16). The fingerprint covers **the whole assembled
    /// request** — which already contains the evidence bodies, the related notes and the skill file —
    /// plus the model and prompt version. So editing a record's text, a newly related note appearing, or
    /// the skill file changing all produce a different draft rather than a refused duplicate. Stricter
    /// than "the same evidence ids", which name the inputs without covering what is in them.
    public let id: String
    public let skill: String
    /// The evidence ids the operator named (findings and/or friction) — D1.
    public let motivation: [String]
    /// Eval ids that should start passing, **copied from the named evidence records, never model-supplied**
    /// (D6). Empty is normal and honest: machine-mined findings carry no linked eval until one is written.
    public let expected: [String]
    public let model: String
    public let promptVersion: String
    /// Identifies **the request that produced this draft** — the assembled instructions, the model and
    /// the instruction version. Stored so a later run can tell "the same request again" from "a different
    /// request that happens to name the same records", without re-deriving anything.
    public let requestFingerprint: String
    public let edits: [EditProposal]

    public init(id: String, skill: String, motivation: [String], expected: [String],
                model: String, promptVersion: String, requestFingerprint: String,
                edits: [EditProposal]) {
        self.id = id; self.skill = skill; self.motivation = motivation; self.expected = expected
        self.model = model; self.promptVersion = promptVersion
        self.requestFingerprint = requestFingerprint; self.edits = edits
    }
}

/// One content-anchored edit: replace `currentExcerpt` (which must match its target file **exactly once**)
/// with `proposedText`. Content anchors survive reordering, unlike line-offset patches.
public struct EditProposal: Codable, Sendable, Equatable {
    /// The file this edit targets. **This version accepts only the skill's `SKILL.md`** (D4a); an edit
    /// naming anything else is rejected at parse time, and the prompt is scoped to match (D11).
    public let path: String
    /// Where the anchor was found, e.g. `142` or `142-145`. **Derived from the verified match**, never
    /// taken from the reply — the same don't-trust-model-supplied-locations rule as `expected` (D6).
    public let skillMdLines: String
    public let currentExcerpt: String
    public let proposedText: String
    public let rationale: String
    /// Which of the set's `motivation` ids this specific edit addresses — **validated to be a subset**;
    /// an id the operator never named is dropped rather than recorded (D6's rule, applied per edit).
    public let addresses: [String]

    public init(path: String, skillMdLines: String, currentExcerpt: String,
                proposedText: String, rationale: String, addresses: [String]) {
        self.path = path; self.skillMdLines = skillMdLines; self.currentExcerpt = currentExcerpt
        self.proposedText = proposedText; self.rationale = rationale; self.addresses = addresses
    }
}
