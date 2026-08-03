import Testing
import Foundation
@testable import EDDCore

/// The two F41 boundary shapes: the drafted file (`skillet.proposal/1`, provisional) and the command
/// summary (`skillet.suggest/1`, stable). Goldens enumerate **every** field — an omitted field is an
/// unenforced shape.
@Suite("suggest formats — drafted file + command summary")
struct ProposalFormatTests {
    func sampleSet() -> ProposalSet {
        ProposalSet(
            id: "2026-07-29-docc-articles-a3f9",
            skill: "docc-articles",
            motivation: ["2026-06-09-rule-of-three-density"],
            expected: ["rule-of-three-density"],
            model: "claude-opus-5",
            promptVersion: "v1",
            requestFingerprint: "9f3a17c2",
            edits: [EditProposal(
                path: "SKILL.md",
                skillMdLines: "142",
                currentExcerpt: "Always use the rule of three.",
                proposedText: "Use the rule of three when the density guidance calls for it.",
                rationale: "The absolute phrasing drove over-application; ground it in density.",
                addresses: ["2026-06-09-rule-of-three-density"])])
    }

    @Test("Drafted file: golden shape with every field")
    func proposalGolden() throws {
        let golden = """
        {"schema": "skillet.proposal/1",
         "id": "2026-07-29-docc-articles-a3f9",
         "skill": "docc-articles",
         "motivation": ["2026-06-09-rule-of-three-density"],
         "expected": ["rule-of-three-density"],
         "model": "claude-opus-5",
         "prompt_version": "v1",
         "request_fingerprint": "9f3a17c2",
         "edits": [{
           "path": "SKILL.md",
           "skill_md_lines": "142",
           "current_excerpt": "Always use the rule of three.",
           "proposed_text": "Use the rule of three when the density guidance calls for it.",
           "rationale": "The absolute phrasing drove over-application; ground it in density.",
           "addresses": ["2026-06-09-rule-of-three-density"]
         }]}
        """
        #expect(try jsonSemanticEqual(try SkilletJSON.encode(sampleSet()), golden))
    }

    /// §5a: `Envelope` stamps `schema`, so the payload must NOT also encode it — otherwise the key is
    /// emitted twice and one value silently clobbers the other.
    @Test("Drafted file: exactly one `schema` key, and a hand-authored file that spells it out still decodes")
    func proposalSchemaKeyIsNotDoubled() throws {
        let encoded = try SkilletJSON.encode(sampleSet())
        #expect(encoded.components(separatedBy: "\"schema\"").count - 1 == 1)
        #expect(encoded.contains("\"schema\":\"skillet.proposal/1\""))

        // Hand-authored input (the design says these may be written by hand) carries `schema`; the
        // decoder ignores keys the type doesn't model, so it round-trips.
        let handWritten = """
        {"schema":"skillet.proposal/1","id":"x","skill":"s","motivation":[],"expected":[],
         "model":"m","prompt_version":"v1","request_fingerprint":"abc12345","edits":[]}
        """
        let back = try SkilletJSON.decode(ProposalSet.self, from: handWritten)
        #expect(back.id == "x" && back.edits.isEmpty)
    }

    @Test("Drafted file: round-trips through the shared codec")
    func proposalRoundTrip() throws {
        let encoded = try SkilletJSON.encode(sampleSet())
        #expect(try SkilletJSON.decode(ProposalSet.self, from: encoded) == sampleSet())
    }

    // MARK: - the stable command summary

    func sampleResult(dryRun: Bool = false) -> SuggestResult {
        SuggestResult(
            skill: "docc-articles",
            proposalId: dryRun ? nil : "2026-07-29-docc-articles-a3f9",
            path: dryRun ? nil : ".skillet/proposals/2026-07-29-docc-articles-a3f9.json",
            edits: dryRun ? 0 : 1,
            motivation: ["2026-06-09-rule-of-three-density"],
            expected: ["rule-of-three-density"],
            model: "claude-opus-5",
            promptVersion: "v1",
            estimatedPromptBytes: 4096,
            dryRun: dryRun,
            disclosures: [Disclosure(subject: "findings/2026-05-01-x.md", reason: "is a symbolic link — not followed")])
    }

    @Test("Command summary: golden shape with every field")
    func suggestResultGolden() throws {
        let golden = """
        {"schema": "skillet.suggest/1",
         "skill": "docc-articles",
         "proposal_id": "2026-07-29-docc-articles-a3f9",
         "path": ".skillet/proposals/2026-07-29-docc-articles-a3f9.json",
         "edits": 1,
         "motivation": ["2026-06-09-rule-of-three-density"],
         "expected": ["rule-of-three-density"],
         "model": "claude-opus-5",
         "prompt_version": "v1",
         "estimated_prompt_bytes": 4096,
         "dry_run": false,
         "disclosures": [{"subject": "findings/2026-05-01-x.md", "reason": "is a symbolic link — not followed"}]}
        """
        #expect(try jsonSemanticEqual(try SkilletJSON.encode(sampleResult()), golden))
    }

    @Test("Command summary: a dry run reports no id and no path; a real draft reports both")
    func suggestResultDryRunNulls() throws {
        let dry = try SkilletJSON.encode(sampleResult(dryRun: true))
        #expect(dry.contains("\"dry_run\":true"))
        #expect(dry.contains("\"proposal_id\":null") && dry.contains("\"path\":null"))
        let real = try SkilletJSON.encode(sampleResult())
        #expect(real.contains("\"proposal_id\":\"2026-07-29-docc-articles-a3f9\""))
    }

    /// The stable summary must never carry the provisional file's content — that coupling is exactly
    /// what would turn a tweak to the drafted shape into a breaking change here.
    @Test("Command summary: edit content is NOT embedded — only the count and the path")
    func suggestResultDoesNotEmbedEdits() throws {
        let encoded = try SkilletJSON.encode(sampleResult())
        #expect(!encoded.contains("current_excerpt"))
        #expect(!encoded.contains("proposed_text"))
        #expect(encoded.contains("\"edits\":1"))
    }

    @Test("Command summary: round-trips through the shared codec")
    func suggestResultRoundTrip() throws {
        let encoded = try SkilletJSON.encode(sampleResult())
        #expect(try SkilletJSON.decode(SuggestResult.self, from: encoded) == sampleResult())
    }

    // MARK: - the shared intake rule

    /// "Contents must match where it lives", one level up from the id ↔ filename check. Shared because
    /// both intake paths ask it; it returns the fact only, because they must answer it differently.
    @Test("A record declares which skill it belongs to — the folder it sits in does not decide")
    func belongsToRule() {
        let header = EvidenceHeader(id: "2026-06-09-x", skill: "docc-articles", domain: "d",
                                    lever: .skillMd, state: .logged)
        let note = FrictionEvent(header: header)
        #expect(note.belongs(to: "docc-articles"))
        #expect(!note.belongs(to: "other-skill"), "a record filed under another skill is misfiled")
    }
}
