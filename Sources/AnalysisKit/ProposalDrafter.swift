import Foundation
import EDDCore

/// One already-loaded evidence record (a machine-mined finding **or** a hand-written friction note —
/// `--from` accepts either, D1). Loading and decoding happen in the executable; this kit stays pure and
/// interop-free, so it only ever sees decoded values.
public struct DraftEvidence: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case finding, friction

        /// How a record of this kind is described **to the model**, in plain words rather than this
        /// project's vocabulary. The prompt's one job here is to say where an observation came from —
        /// mined by a machine, or written down by a person — and "friction" carries that only to someone
        /// who already knows the term. Shared by every section that names a record, because the two
        /// sections used to disagree: the same hand-written note was "friction" when you named it and a
        /// "human note" when the session join found it.
        public var described: String { self == .finding ? "finding" : "human note" }
    }
    public let id: String
    public let kind: Kind
    /// The record's prose body — the concrete failure detail a critique needs (D1).
    public let body: String
    /// The eval this record is linked to, when someone has written one. Usually `nil`.
    public let eval: String?
    public let sessions: [String]

    public init(id: String, kind: Kind, body: String, eval: String?, sessions: [String]) {
        self.id = id; self.kind = kind; self.body = body; self.eval = eval; self.sessions = sessions
    }

    /// Build drafting context from a decoded record.
    ///
    /// **The label comes from the record, never from the folder it was found in.** `kind` is the only
    /// signal the drafting prompt gets about where an observation came from — machine-mined or written
    /// by a person — so a finding misfiled under `friction/` must still be described as a finding. The
    /// folder is a filing convention; the record is the fact. Every intake path builds through here so
    /// that staying consistent is the default rather than something each one has to remember.
    public init(record: any Evidence, body: String) {
        self.init(id: record.header.id,
                  kind: record is Finding ? .finding : .friction,
                  body: body,
                  eval: record.header.eval,
                  sessions: record.header.sessions)
    }
}

/// Everything the pure drafter needs, already read from disk by the shell.
public struct DraftContext: Sendable, Equatable {
    public let skill: String
    public let skillMarkdown: String
    /// The records the operator named with `--from`.
    public let named: [DraftEvidence]
    /// Friction notes joined by shared session, with the already-named ids removed (A22).
    public let linkedFriction: [DraftEvidence]
    public let model: String
    /// Injected so ids are deterministic in tests (the triage engine's precedent).
    public let runDate: String

    public init(skill: String, skillMarkdown: String, named: [DraftEvidence],
                linkedFriction: [DraftEvidence], model: String, runDate: String) {
        self.skill = skill; self.skillMarkdown = skillMarkdown; self.named = named
        self.linkedFriction = linkedFriction; self.model = model; self.runDate = runDate
    }
}

/// A parsed, validated reply: the edits worth keeping plus a reason for everything dropped.
public struct ParsedDraft: Sendable, Equatable {
    public let edits: [EditProposal]
    public let disclosures: [Disclosure]
    public init(edits: [EditProposal], disclosures: [Disclosure]) {
        self.edits = edits; self.disclosures = disclosures
    }
}

/// The reply could not be read as a draft at all.
public struct DraftParseError: Error, Sendable, Equatable {
    /// A short excerpt of what actually came back, so the failure is diagnosable without a re-run.
    public let excerpt: String
    public init(excerpt: String) { self.excerpt = excerpt }
}

/// The **pure** drafting core (design §11 assigns proposal drafting here): prompt assembly, reply
/// parsing, exact-once anchor validation, and id derivation over already-loaded inputs. No filesystem,
/// no model call, no C++-interop imports — the shell owns all of those.
public enum ProposalDrafter {
    /// Bumped deliberately when the instructions change; stamped into every drafted set for provenance
    /// (constitution II), mirroring the grader's `promptVersion`.
    public static let promptVersion = "v1"

    /// Only this file may be edited in F41 (D4a); an edit naming anything else is dropped with a reason.
    public static let editableFileName = "SKILL.md"

    // MARK: - Prompt

    /// The instructions. **Scoped to what we actually accept (D11):** they ask for deletion/tightening
    /// *within this one file* and never mention moving material into a separate reference file — telling
    /// the model to do something we always reject would make it guess and degrade every reply, including
    /// the edits we keep.
    public static func prompt(_ context: DraftContext) -> String {
        var sections: [String] = []
        sections.append("""
        You are drafting a minimal, surgical edit to one instruction file for an AI agent skill.

        Rules:
        - Edit ONLY the file named \(editableFileName), shown below. Do not propose edits to any other file.
        - Prefer deleting or tightening prose that isn't earning its place over adding more.
        - Generalize from the observed evidence; explain why the change helps.
        - Draft ONLY against the evidence below. Never invent a failure that is not shown.
        - Each edit must quote an excerpt that appears EXACTLY ONCE in the file, verbatim.

        Reply with JSON only — no prose, no explanation outside the JSON:
        {"edits": [{"current_excerpt": "<verbatim text from the file>",
                    "proposed_text": "<replacement>",
                    "rationale": "<why this helps>",
                    "addresses": ["<evidence id>"]}]}
        """)
        sections.append("## The file to edit (\(editableFileName))\n\n\(context.skillMarkdown)")
        // **Sorted, so the request is canonical for a given set of records.** Identity is bound to the
        // request, so if the order you happened to type ids in changed the request, it would change the
        // draft's identity too — re-introducing the order sensitivity removed earlier. Sorting also makes
        // the request reproducible, which is what lets "the same request again" mean anything.
        for record in context.named.sorted(by: { $0.id < $1.id }) {
            sections.append("## Observed \(record.kind.described) — id: \(record.id)\n\n\(record.body)")
        }
        for record in context.linkedFriction.sorted(by: { $0.id < $1.id }) {
            // The heading follows the RECORD, exactly as the named sections above do — and uses the same
            // words, from the same helper. These are gathered by scanning the friction folder, so calling
            // every one of them a "human note" was describing the folder rather than the thing found in it.
            sections.append("## Related \(record.kind.described) (same session) — id: \(record.id)\n\n\(record.body)")
        }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Derived set fields

    /// Eval ids copied from the named records — **never model-supplied** (D6). Empty is normal: a
    /// machine-mined finding carries no linked eval until someone writes one.
    public static func expected(from named: [DraftEvidence]) -> [String] {
        // Drop blanks as well as absent values: an empty entry is not a test name, and letting one
        // through would print an empty item and hand the feature that proves fixes something to look up.
        Array(Set(named.compactMap { $0.eval?.trimmingCharacters(in: .whitespacesAndNewlines) }
                       .filter { !$0.isEmpty })).sorted()
    }

    /// A fingerprint of **the request actually sent** — the assembled instructions (which already contain
    /// the evidence bodies, the related notes and the skill file) plus the model and instruction version.
    ///
    /// Identity is bound to the request, not to the *names* of its parts. Naming only the evidence ids
    /// missed three things that change what gets sent: a record's body being edited, a newly related note
    /// being pulled in, and the skill file itself changing — any of which produced a materially different
    /// request under the same name, reported as one you had already made. Binding the key to a fingerprint
    /// of the payload, covering everything that makes the request unique, is the standard idempotency rule.
    ///
    /// Deliberately **not** derived from the drafted edits: model output is not deterministic, so the same
    /// request routinely yields different edits — comparing those would report "a different draft" almost
    /// every time the inputs were in fact identical, which is precisely backwards.
    public static func requestFingerprint(prompt: String, model: String,
                                          promptVersion: String = promptVersion) -> String {
        fingerprint([prompt, model, promptVersion].joined(separator: "\u{1}"))
    }

    /// `<run-date>-<skill>-<fingerprint>` where the fingerprint identifies the request (above).
    public static func setId(runDate: String, skill: String, requestFingerprint: String) -> String {
        "\(runDate)-\(skill)-\(requestFingerprint)"
    }

    /// FNV-1a, the full 32 bits as 8 hex chars. Non-cryptographic on purpose — a filename discriminator,
    /// not a security control — so it adds no dependency, and unlike Swift's `Hasher` it is stable across
    /// runs. **Width matters:** at 4 chars (16 bits) two *different* drafts would land on the same name
    /// after only a few hundred per skill-day, and the second would be refused as though it were a repeat.
    /// 32 bits moves that from plausible to negligible — but length alone is never the whole answer, so
    /// the writer also compares inputs before claiming "already drafted" (the idempotency-key rule: same
    /// key with different inputs is an error in its own right, not a duplicate).
    static func fingerprint(_ text: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash ^= UInt32(byte); hash = hash &* 16_777_619 }
        return String(format: "%08x", hash)
    }

    /// Friction notes related to the named records, minus ids already named (D1/A22). The *rule* for
    /// "related" is `EvidenceLink.sharesSession` — see there for why that one line is shared while this
    /// filtering is not.
    public static func linkedFriction(sessions: Set<String>, friction: [DraftEvidence],
                                      excluding named: Set<String> = []) -> [DraftEvidence] {
        friction
            .filter { !named.contains($0.id) && EvidenceLink.sharesSession($0.sessions, sessions) }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Reply parsing

    private struct ReplyEdit: Decodable {
        let path: String?
        let currentExcerpt: String
        let proposedText: String
        let rationale: String?
        let addresses: [String]?
    }
    private struct Reply: Decodable { let edits: [ReplyEdit] }

    /// **Bounded normalization (D10):** trim, strip one optional surrounding code fence, then require the
    /// remainder to parse. Deliberately no scanning for the first brace-block anywhere in the reply — that
    /// could pick up an example quoted in the model's own prose, or a truncated fragment, and draft from
    /// the wrong thing. Maximal leniency hides errors instead of surfacing them.
    static func normalizedJSON(_ reply: String) -> String {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        var lines = text.components(separatedBy: "\n")
        lines.removeFirst()                                       // ``` or ```json
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    /// Parse + validate. Every rejection carries its reason; an unreadable reply is a thrown error the
    /// command maps to a bad-artifact exit.
    public static func parse(reply: String, context: DraftContext) throws -> ParsedDraft {
        let json = normalizedJSON(reply)
        guard let data = json.data(using: .utf8),
              let decoded = try? SkilletJSON.decoder().decode(Reply.self, from: data) else {
            throw DraftParseError(excerpt: String(json.prefix(200)))
        }
        let namedIds = Set(context.named.map(\.id))
        var edits: [EditProposal] = []
        var disclosures: [Disclosure] = []

        for (index, candidate) in decoded.edits.enumerated() {
            let label = "edit \(index)"
            // Single-file scope (D4a): the prompt says so, and this is the backstop, not the mechanism.
            if let path = candidate.path, path != editableFileName {
                disclosures.append(Disclosure(
                    subject: label,
                    reason: "targets '\(path)' — this version edits only \(editableFileName); dropped"))
                continue
            }
            switch anchor(candidate.currentExcerpt, in: context.skillMarkdown) {
            case let .found(lines):
                // `addresses` is validated to the ids the operator actually named — an id the model
                // invented is dropped rather than recorded (D6's rule, applied per edit).
                // Three outcomes, not two. **Invented** ids are fabrication — the edit cannot be traced to
                // anything observed, so it goes, which is what the observed-evidence-only rule demands.
                // An **omitted** field is a formatting lapse, not fabrication: the named evidence is
                // literally all that was in the request, so attributing the edit to it is true, and
                // discarding good work over a missing field would be the worse trade.
                let claimed = candidate.addresses ?? []
                let addresses = claimed.filter(namedIds.contains).sorted()
                if !claimed.isEmpty && addresses.isEmpty {
                    disclosures.append(Disclosure(
                        subject: label,
                        reason: "names evidence that was not provided (\(claimed.joined(separator: ", "))) — dropped, since it cannot be traced to anything observed"))
                    continue
                }
                let attributed = addresses.isEmpty ? namedIds.sorted() : addresses
                if addresses.isEmpty {
                    disclosures.append(Disclosure(
                        subject: label,
                        reason: "named no evidence — attributed to the records you provided, which is all the request contained"))
                }
                edits.append(EditProposal(
                    path: editableFileName,
                    skillMdLines: lines,
                    currentExcerpt: candidate.currentExcerpt,
                    proposedText: candidate.proposedText,
                    rationale: candidate.rationale ?? "",
                    addresses: attributed))
            case .missing:
                disclosures.append(Disclosure(
                    subject: label, reason: "its quoted excerpt does not appear in \(editableFileName) — dropped (drift)"))
            case let .ambiguous(count, capped):
                // Say "at least" once the scan is capped — under-reporting a count is exactly the defect
                // the accurate-count fix removed; the cap must not quietly reintroduce it.
                let howMany = capped ? "at least \(count)" : "\(count)"
                disclosures.append(Disclosure(
                    subject: label, reason: "its quoted excerpt appears \(howMany) times in \(editableFileName) — dropped (ambiguous)"))
            }
        }
        return ParsedDraft(edits: edits, disclosures: disclosures)
    }

    enum AnchorResult: Equatable { case found(lines: String), missing, ambiguous(count: Int, capped: Bool) }

    /// Exact-once match, and the line span of the hit — derived here rather than trusted from the reply.
    static func anchor(_ excerpt: String, in text: String) -> AnchorResult {
        guard !excerpt.isEmpty else { return .missing }
        // Count **every** occurrence, not just the first two: the disclosure exists to help someone
        // narrow the quoted text, and "appears 2 times" when it appears 9 is actively misleading. Capped
        // so a pathological excerpt/file pair can't make this expensive; at the cap the message says
        // "at least N", which stays true rather than under-reporting.
        let scanCap = 1_000
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while ranges.count < scanCap, let found = text.range(of: excerpt, range: searchStart..<text.endIndex) {
            ranges.append(found)
            searchStart = found.upperBound
        }
        guard let only = ranges.first else { return .missing }
        if ranges.count > 1 { return .ambiguous(count: ranges.count, capped: ranges.count == scanCap) }
        let startLine = text[text.startIndex..<only.lowerBound].filter { $0 == "\n" }.count + 1
        let endLine = startLine + text[only].filter { $0 == "\n" }.count
        return .found(lines: startLine == endLine ? "\(startLine)" : "\(startLine)-\(endLine)")
    }
}
