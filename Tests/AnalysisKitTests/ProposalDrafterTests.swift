import Testing
import Foundation
import EDDCore
@testable import AnalysisKit

/// The pure drafting core: prompt assembly, reply normalization + parsing, exact-once anchor checking,
/// and id derivation. No I/O, no model — every case is a value in, a value out.
@Suite("ProposalDrafter — the pure drafting core (F41)")
struct ProposalDrafterTests {
    let markdown = """
    ---
    name: docc-articles
    ---
    # Guide

    Always use the rule of three.

    Some other prose that is unique.
    """

    func context(named: [DraftEvidence] = [], linked: [DraftEvidence] = [],
                 markdown: String? = nil) -> DraftContext {
        DraftContext(skill: "docc-articles", skillMarkdown: markdown ?? self.markdown,
                     named: named, linkedFriction: linked, model: "claude-opus-5", runDate: "2026-07-29")
    }
    func finding(_ id: String, eval: String? = nil, sessions: [String] = ["s1"], body: String = "hits=12") -> DraftEvidence {
        DraftEvidence(id: id, kind: .finding, body: body, eval: eval, sessions: sessions)
    }
    func friction(_ id: String, sessions: [String] = ["s1"], body: String = "I hand-fixed the intro.") -> DraftEvidence {
        DraftEvidence(id: id, kind: .friction, body: body, eval: nil, sessions: sessions)
    }

    // MARK: - prompt

    @Test("Prompt carries the file, the named evidence bodies, and the linked human notes; it is deterministic")
    func promptContents() {
        let ctx = context(named: [finding("f1", body: "hits=12 recordings=3/5")],
                          linked: [friction("fr1", body: "I had to rewrite the intro by hand.")])
        let text = ProposalDrafter.prompt(ctx)
        #expect(text.contains("Always use the rule of three."))          // the file itself
        #expect(text.contains("hits=12 recordings=3/5"))                 // the finding's body
        #expect(text.contains("I had to rewrite the intro by hand."))    // the human note's body
        #expect(text.contains("f1") && text.contains("fr1"))             // both ids labelled
        #expect(ProposalDrafter.prompt(ctx) == text)                     // deterministic
    }

    /// D11: the instructions must match what the validator accepts, or the model is told to do something
    /// we always reject — which makes it guess and degrades every reply, not just the dropped parts.
    @Test("Prompt is scoped to the accepted behavior — no 'move it to a reference file' phrasing")
    func promptMatchesValidation() {
        let text = ProposalDrafter.prompt(context(named: [finding("f1")]))
        #expect(text.contains("deleting or tightening"))
        #expect(text.lowercased().contains("edit only"))
        #expect(!text.lowercased().contains("references/"))
        #expect(!text.lowercased().contains("reference file"))
        #expect(text.contains("JSON only"))
    }

    // MARK: - expected / id

    @Test("`expected` is copied from the named records, sorted + de-duplicated; empty when none carry one")
    func expectedProvenance() {
        #expect(ProposalDrafter.expected(from: [finding("a", eval: "z"), finding("b", eval: "y"), finding("c", eval: "z")])
                == ["y", "z"])
        #expect(ProposalDrafter.expected(from: [finding("a"), finding("b")]).isEmpty)   // normal, not a defect
    }

    @Test("Identity follows the REQUEST: same request ⇒ same id; any change to what is sent ⇒ a new one")
    func identityFollowsTheRequest() {
        let base = ProposalDrafter.requestFingerprint(prompt: "instructions + evidence + file", model: "m")
        #expect(ProposalDrafter.requestFingerprint(prompt: "instructions + evidence + file", model: "m") == base)
        // Each of these changes what actually gets sent, so each must produce a different draft identity.
        #expect(ProposalDrafter.requestFingerprint(prompt: "instructions + MORE evidence + file", model: "m") != base)
        #expect(ProposalDrafter.requestFingerprint(prompt: "instructions + evidence + file", model: "other") != base)
        #expect(ProposalDrafter.requestFingerprint(prompt: "instructions + evidence + file", model: "m",
                                                   promptVersion: "v2") != base)
        #expect(ProposalDrafter.setId(runDate: "2026-08-01", skill: "s", requestFingerprint: base)
                == "2026-08-01-s-\(base)")
    }

    @Test("Fingerprint is process-stable (a hand-rolled hash, not Swift's per-process-seeded one)")
    func fingerprintIsStable() {
        #expect(ProposalDrafter.fingerprint("a,b,m,v1") == ProposalDrafter.fingerprint("a,b,m,v1"))
        #expect(ProposalDrafter.fingerprint("a") != ProposalDrafter.fingerprint("b"))
        #expect(ProposalDrafter.fingerprint("a").count == 8, "narrow fingerprints make distinct drafts collide")
    }

    // MARK: - friction join

    @Test("Linked notes share a session and never repeat an id the operator already named")
    func frictionJoin() {
        let linked = ProposalDrafter.linkedFriction(
            sessions: ["s1"],
            friction: [friction("fr1", sessions: ["s1"]), friction("fr2", sessions: ["other"]), friction("named", sessions: ["s1"])],
            excluding: ["named"])
        #expect(linked.map(\.id) == ["fr1"])
    }

    // MARK: - reply normalization + parsing

    @Test("A reply wrapped in one code fence parses; leading prose does not (no salvage)")
    func replyNormalization() throws {
        let body = #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"Use it when density calls for it.","rationale":"why","addresses":["f1"]}]}"#
        let fenced = "```json\n\(body)\n```"
        let ctx = context(named: [finding("f1")])
        #expect(try ProposalDrafter.parse(reply: fenced, context: ctx).edits.count == 1)
        #expect(try ProposalDrafter.parse(reply: body, context: ctx).edits.count == 1)

        // Leading prose is NOT salvaged — scanning for a brace-block could pick up an example the model
        // quoted in its own explanation.
        #expect(throws: DraftParseError.self) {
            try ProposalDrafter.parse(reply: "Here's the JSON:\n\(body)", context: ctx)
        }
        #expect(throws: DraftParseError.self) { try ProposalDrafter.parse(reply: "", context: ctx) }
    }

    @Test("An unreadable reply carries an excerpt of what actually came back")
    func parseErrorCarriesExcerpt() {
        do {
            _ = try ProposalDrafter.parse(reply: "total nonsense", context: context())
            Issue.record("expected a parse failure")
        } catch let error as DraftParseError {
            #expect(error.excerpt.contains("total nonsense"))
        } catch { Issue.record("wrong error type") }
    }

    @Test("Anchor validation: exactly once accepted with its line span; missing and repeated are dropped with a reason")
    func anchorValidation() throws {
        let ctx = context(named: [finding("f1")])
        func reply(_ excerpt: String) -> String {
            #"{"edits":[{"current_excerpt":"\#(excerpt)","proposed_text":"x","rationale":"r","addresses":["f1"]}]}"#
        }
        let ok = try ProposalDrafter.parse(reply: reply("Always use the rule of three."), context: ctx)
        #expect(ok.edits.count == 1)
        #expect(ok.edits[0].skillMdLines == "6")            // derived from the verified match, not the reply
        #expect(ok.disclosures.isEmpty)

        let missing = try ProposalDrafter.parse(reply: reply("text that is not there"), context: ctx)
        #expect(missing.edits.isEmpty)
        #expect(missing.disclosures.first?.reason.contains("does not appear") == true)

        // "Guide" appears once; use a string that genuinely repeats.
        let repeated = context(named: [finding("f1")], markdown: "dup\nmiddle\ndup\n")
        let ambiguous = try ProposalDrafter.parse(reply: reply("dup"), context: repeated)
        #expect(ambiguous.edits.isEmpty)
        #expect(ambiguous.disclosures.first?.reason.contains("ambiguous") == true)
    }

    @Test("An edit naming another file is dropped with a reason; SKILL.md is accepted")
    func singleFileScope() throws {
        let ctx = context(named: [finding("f1")])
        func reply(_ path: String) -> String {
            #"{"edits":[{"path":"\#(path)","current_excerpt":"Always use the rule of three.","proposed_text":"x","rationale":"r","addresses":["f1"]}]}"#
        }
        let other = try ProposalDrafter.parse(reply: reply("references/deep.md"), context: ctx)
        #expect(other.edits.isEmpty)
        #expect(other.disclosures.first?.reason.contains("edits only SKILL.md") == true)
        #expect(try ProposalDrafter.parse(reply: reply("SKILL.md"), context: ctx).edits.count == 1)
    }

    @Test("`addresses` keeps only ids the operator actually named — invented ids are dropped")
    func addressesAreValidated() throws {
        let ctx = context(named: [finding("f1")])
        let reply = #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"x","rationale":"r","addresses":["f1","invented-id"]}]}"#
        #expect(try ProposalDrafter.parse(reply: reply, context: ctx).edits[0].addresses == ["f1"])
    }

    @Test("A partial reply keeps the valid edits and drops the rest with reasons")
    func partialReply() throws {
        let ctx = context(named: [finding("f1")])
        let reply = """
        {"edits":[
          {"current_excerpt":"Always use the rule of three.","proposed_text":"a","rationale":"r","addresses":["f1"]},
          {"current_excerpt":"nowhere to be found","proposed_text":"b","rationale":"r","addresses":["f1"]}
        ]}
        """
        let parsed = try ProposalDrafter.parse(reply: reply, context: ctx)
        #expect(parsed.edits.count == 1)
        #expect(parsed.disclosures.count == 1)
    }

    @Test("A repeated excerpt reports its TRUE count, not always 2 — the message exists to help narrow it")
    func ambiguousCountIsAccurate() throws {
        let ctx = context(named: [finding("f1")], markdown: "dup\na\ndup\nb\ndup\nc\ndup\n")
        let reply = #"{"edits":[{"current_excerpt":"dup","proposed_text":"x","rationale":"r","addresses":["f1"]}]}"#
        let parsed = try ProposalDrafter.parse(reply: reply, context: ctx)
        #expect(parsed.edits.isEmpty)
        #expect(parsed.disclosures.first?.reason.contains("appears 4 times") == true,
                "got: \(parsed.disclosures.first?.reason ?? "none")")
        // And the direct result, so the count isn't only checked through the message.
        #expect(ProposalDrafter.anchor("dup", in: "dup\na\ndup\nb\ndup\nc\ndup\n") == .ambiguous(count: 4, lines: ["1", "3", "5", "7"], capped: false))
    }

    @Test("The shared 'related evidence' rule is one place, and both filterings still behave")
    func sharedSessionRule() {
        #expect(EvidenceLink.sharesSession(["a", "b"], ["b"]))
        #expect(!EvidenceLink.sharesSession(["a"], ["b"]))
        #expect(!EvidenceLink.sharesSession([] as [String], ["b"]))
    }

    @Test("Past the scan cap the count is reported as a floor — never a number lower than the truth")
    func cappedCountSaysAtLeast() throws {
        let many = String(repeating: "dup\n", count: 1_200)
        let ctx = context(named: [finding("f1")], markdown: many)
        let reply = #"{"edits":[{"current_excerpt":"dup","proposed_text":"x","rationale":"r","addresses":["f1"]}]}"#
        let parsed = try ProposalDrafter.parse(reply: reply, context: ctx)
        #expect(parsed.disclosures.first?.reason.contains("at least 1000 times") == true,
                "got: \(parsed.disclosures.first?.reason ?? "none")")
    }

    @Test("An edit naming evidence that was never provided is dropped; one naming none is attributed")
    func untraceableEditsAreDroppedButOmissionsAreNot() throws {
        let ctx = context(named: [finding("f1")])
        func reply(_ addresses: String) -> String {
            #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"x","rationale":"r"\#(addresses)}]}"#
        }
        // Invented ids = fabrication: nothing observed backs the edit, so it goes.
        let invented = try ProposalDrafter.parse(reply: reply(#","addresses":["made-up"]"#), context: ctx)
        #expect(invented.edits.isEmpty)
        #expect(invented.disclosures.first?.reason.contains("not provided") == true)

        // Omitted = a formatting lapse: the named evidence is all the request contained, so keep the
        // edit and attribute it there rather than discarding usable work.
        let omitted = try ProposalDrafter.parse(reply: reply(""), context: ctx)
        #expect(omitted.edits.count == 1)
        #expect(omitted.edits[0].addresses == ["f1"])
        #expect(omitted.disclosures.first?.reason.contains("named no evidence") == true)
    }

    // MARK: - the shared intake rule

    func header(_ id: String) -> EvidenceHeader {
        EvidenceHeader(id: id, skill: "docc-articles", domain: "d", lever: .skillMd, state: .logged,
                       sessions: ["s1"], eval: "e1")
    }

    /// The label the prompt shows is derived from the RECORD, not from the folder the record was read
    /// from — a finding misfiled under `friction/` is still a finding. Every intake path builds through
    /// this initialiser so the two can never disagree.
    @Test("A record's own type decides whether it is described as a finding or as a friction note")
    func labelComesFromTheRecord() {
        let finding = Finding(header: header("2026-06-09-a"), source: .scorer, confidence: .high)
        let note = FrictionEvent(header: header("2026-06-09-b"))
        #expect(DraftEvidence(record: finding, body: "b").kind == .finding)
        #expect(DraftEvidence(record: note, body: "b").kind == .friction)
    }

    @Test("Building from a record carries the id, body, eval and sessions across unchanged")
    func recordInitCarriesEveryField() {
        let built = DraftEvidence(record: FrictionEvent(header: header("2026-06-09-c")), body: "the body")
        #expect(built.id == "2026-06-09-c")
        #expect(built.body == "the body")
        #expect(built.eval == "e1")
        #expect(built.sessions == ["s1"])
    }

    /// The session join is gathered by scanning the friction folder, so its heading used to call every
    /// record a "human note" — describing the folder rather than the record found in it.
    @Test("A linked record is introduced by what it IS, not by the folder it was gathered from")
    func linkedHeadingFollowsTheRecord() {
        func prompt(_ kind: DraftEvidence.Kind) -> String {
            ProposalDrafter.prompt(DraftContext(
                skill: "demo", skillMarkdown: "# Guide",
                named: [DraftEvidence(id: "2026-06-09-a", kind: .finding, body: "n", eval: nil, sessions: ["s1"])],
                linkedFriction: [DraftEvidence(id: "2026-06-10-b", kind: kind, body: "linked body",
                                               eval: nil, sessions: ["s1"])],
                model: "m", runDate: "2026-06-11"))
        }
        #expect(prompt(.friction).contains("## Related human note (same session) — id: 2026-06-10-b"))
        #expect(prompt(.finding).contains("## Related finding (same session) — id: 2026-06-10-b"))
        #expect(!prompt(.finding).contains("human note"), "a mined finding is not something a person wrote")
    }

    /// The named section used the project's own vocabulary ("friction") while the linked section used
    /// plain words ("human note"), so the same hand-written note was introduced two different ways
    /// depending on how it got into the request.
    @Test("A hand-written note is described the same way whether you name it or the session join finds it")
    func bothSectionsUseTheSameWords() {
        let note = DraftEvidence(id: "2026-06-10-b", kind: .friction, body: "body",
                                 eval: nil, sessions: ["s1"])
        let text = ProposalDrafter.prompt(DraftContext(
            skill: "demo", skillMarkdown: "# Guide",
            named: [note],
            linkedFriction: [DraftEvidence(id: "2026-06-11-c", kind: .friction, body: "body2",
                                           eval: nil, sessions: ["s1"])],
            model: "m", runDate: "2026-06-12"))
        #expect(text.contains("## Observed human note — id: 2026-06-10-b"))
        #expect(text.contains("## Related human note (same session) — id: 2026-06-11-c"))
        #expect(!text.contains("friction"), "the project's own jargon should not reach the model")
    }

    /// The instructions tell the model to "prefer deleting or tightening prose", and a deletion is an
    /// edit whose replacement is empty. That works today only because nothing rejects it — no test said
    /// so, and a well-meant "an edit must propose something" guard would have silently removed the
    /// behaviour the instructions ask for.
    @Test("A deletion — an edit that replaces text with nothing — is kept, not dropped")
    func deletionEditSurvives() throws {
        let context = DraftContext(
            skill: "demo", skillMarkdown: "# Guide\n\nAlways use the rule of three.\n",
            named: [DraftEvidence(id: "2026-06-09-slop", kind: .finding, body: "b",
                                  eval: nil, sessions: ["s1"])],
            linkedFriction: [], model: "m", runDate: "2026-06-10")
        let parsed = try ProposalDrafter.parse(
            reply: #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"","rationale":"dead prose","addresses":["2026-06-09-slop"]}]}"#,
            context: context)
        #expect(parsed.edits.count == 1, "a deletion is what the instructions ask for, not a no-op")
        #expect(parsed.edits.first?.proposedText == "")
        #expect(parsed.disclosures.isEmpty, "nothing to disclose — the edit was kept")
    }

    /// A model that names one real record and one it invented used to have the invented one removed
    /// without a word — hiding fabrication exactly when it is hardest to notice, because the rest of the
    /// answer looked right.
    @Test("Naming a mix of real and invented evidence says which ones were ignored")
    func partlyInventedEvidenceIsDisclosed() throws {
        let context = DraftContext(
            skill: "demo", skillMarkdown: "# Guide\n\nAlways use the rule of three.\n",
            named: [DraftEvidence(id: "2026-06-09-real", kind: .finding, body: "b", eval: nil, sessions: [])],
            linkedFriction: [], model: "m", runDate: "2026-06-10")
        let parsed = try ProposalDrafter.parse(
            reply: #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"x","rationale":"r","addresses":["2026-06-09-real","2026-01-01-invented"]}]}"#,
            context: context)
        #expect(parsed.edits.count == 1, "the edit is kept — what verified is kept, what did not is surfaced")
        #expect(parsed.edits.first?.addresses == ["2026-06-09-real"], "only the real record is recorded")
        #expect(parsed.disclosures.contains { $0.reason.contains("2026-01-01-invented") },
                "the invented id must be named, not silently removed")
    }
}
