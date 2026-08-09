import Foundation

/// The `skillet.apply/1` machine summary — what an **apply** run did.
///
/// **Its own format, deliberately.** The drafting summary beside it describes a different event: which
/// model was called, which instruction version, how large the request was, whether it was a preview.
/// An apply run knows none of those — it knows which file changed and which edits went into it. The
/// guidance for message shapes is that a payload carries only the facts of the event it describes, and
/// the convention is a shared type tag with a payload per type, which is what the `schema` field here
/// already provides. Folding these fields into the drafting summary would have made half of either
/// payload meaningless depending on a mode the reader had to infer first.
///
/// **Compatibility promise: additive-only; consumers must ignore unrecognized fields.**
public struct ApplyResult: SchemaIdentified, Codable, Sendable, Equatable {
    public static let schema = "skillet.apply/1"

    public let skill: String
    /// The draft this came from, and the file it was read out of.
    public let proposalId: String
    public let proposals: String
    /// Project-relative path of the file that changed.
    public let path: String
    /// Which edits were written, by their number in the draft.
    public let applied: [Int]
    /// The line span each applied edit landed on, in the same order — derived from the match, so it
    /// describes the file as it actually was, not as the draft assumed.
    public let lines: [String]
    /// Always false. Present so a reader never has to ask: this command does not commit or stage, ever.
    public let committed: Bool
    /// True when nothing was written and this is a preview. The discriminator is **in** the payload, so
    /// `applied` reading as "would be applied" is stated rather than inferred — the same shape the
    /// drafting summary beside it already uses for its own preview.
    public let dryRun: Bool
    /// Anything refused, with its reason. Non-empty only alongside a refusal exit code.
    public let disclosures: [Disclosure]

    public init(skill: String, proposalId: String, proposals: String, path: String,
                applied: [Int], lines: [String], committed: Bool = false,
                dryRun: Bool = false, disclosures: [Disclosure] = []) {
        self.skill = skill; self.proposalId = proposalId; self.proposals = proposals
        self.path = path; self.applied = applied; self.lines = lines
        self.committed = committed; self.dryRun = dryRun; self.disclosures = disclosures
    }
}
