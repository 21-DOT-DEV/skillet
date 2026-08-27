import Testing
import Foundation
import EDDCore
import TraceKit
@testable import HarnessKit

/// **What the offline stand-in does when it cannot read or write its own answer.**
///
/// The stand-in replaces the real model so tests can run without spending anything. It answers as one of
/// two kinds: a *with-skill* answer, produced when the skill under test was made available, and a
/// *skill-free* answer, produced when it deliberately was not — the comparison that shows a skill made a
/// difference needs both. A separate safety check disqualifies any skill-free measurement whose answer
/// claims a skill was used, because a skill-free measurement that used the skill measures nothing.
///
/// Both give-up paths here used to hand back the *with-skill* answer regardless of what they were given.
/// So a skill-free answer that failed to encode, or failed to read back, returned claiming a skill had
/// fired — and the run reported a broken measurement when all that had happened was a parsing problem.
/// Neither path can be reached with today's fields, which is exactly why they are pinned: an untested
/// safety net reads as cover, and the next field added decides whether the cover was ever real.
@Suite("The offline stand-in never turns a skill-free answer into a with-skill one")
struct ReplayFallbackTests {
    /// The give-up text is produced by a named function precisely so it can be called here. Reaching it
    /// through normal use would mean adding a field that fails to encode — the very change this guards.
    ///
    /// **Never `demo`.** Both of these used to pass a skill called `demo`, which is the name the canned
    /// session claims when an answer says nothing — so the checks below could not tell a preserved answer
    /// from a discarded one, and passed while the net renamed every skill it touched. Every name here is
    /// deliberately something else.
    @Test("Giving up on writing an answer keeps the kind it was given", arguments: [true, false])
    func lastResortKeepsArm(baseline: Bool) throws {
        let answer = ReplayAdapter.Answer(baseline: baseline, marker: "m", query: "q", firedSkills: ["tidy-notes"])
        let text = ReplayAdapter.lastResort(for: answer)
        let readBack = try #require(ReplayAdapter.decode(text),
                                    "the give-up text must still be readable, or the next step cannot judge it")
        #expect(readBack.baseline == baseline)
    }

    /// **The net must not rename the skill under test.** Dropping the list of skills reached for meant
    /// the answer inherited the canned session's own, which names `demo` — so a run measuring a skill
    /// called anything else came back reporting `demo`, and the routing measurement graded the wrong
    /// name. That is worse than having no net at all, because it reads as cover.
    @Test("Giving up keeps the skills the answer reached for", arguments: [
        ["tidy-notes"], ["alpha", "beta"], [], ["a skill with \"quotes\" in it"]
    ])
    func lastResortKeepsFiredSkills(fired: [String]) throws {
        let answer = ReplayAdapter.Answer(baseline: false, marker: "m", query: "q", firedSkills: fired)
        let trace = try ReplayAdapter().parseTrace(
            RawTrace(harness: "replay", raw: ReplayAdapter.lastResort(for: answer)))
        #expect(trace.skillInvocations.map(\.skill) == fired)
    }

    /// The version marker distinguishes two versions of one skill, and the grader matches on it. Losing
    /// it in the net means the two versions grade identically, which is the whole comparison collapsing.
    @Test("Giving up keeps the version marker the grader matches on")
    func lastResortKeepsMarker() throws {
        let answer = ReplayAdapter.Answer(baseline: false, marker: "v2", query: "q", firedSkills: ["tidy-notes"])
        let trace = try ReplayAdapter().parseTrace(
            RawTrace(harness: "replay", raw: ReplayAdapter.lastResort(for: answer)))
        #expect(trace.turns.contains { $0.text.contains("v2") })
    }

    /// The consequence, not just the field: a skill-free give-up must produce a session that claims
    /// nothing was used — which is what the disqualification check actually looks at.
    @Test("A skill-free give-up produces a session that claims no skill was used")
    func lastResortSkillFreeClaimsNothing() throws {
        let answer = ReplayAdapter.Answer(baseline: true, marker: "m", query: "q", firedSkills: [])
        let trace = try ReplayAdapter().parseTrace(
            RawTrace(harness: "replay", raw: ReplayAdapter.lastResort(for: answer)))
        #expect(trace.skillInvocations.isEmpty,
                "a skill-free answer that claims a skill fired is thrown out as a broken measurement")
    }

    /// Unreadable text is a parsing problem, and the safe reading of it claims nothing. Serving the
    /// with-skill session here reported a broken measurement instead.
    @Test("Text the stand-in cannot read at all is served as a skill-free session",
          arguments: ["", "not json at all", "{", "{\"baseline\":", "[]", "null"])
    func unreadableIsSkillFree(raw: String) throws {
        let trace = try ReplayAdapter().parseTrace(RawTrace(harness: "replay", raw: raw))
        #expect(trace.skillInvocations.isEmpty,
                "unreadable text must not come back claiming a skill was used")
    }

    /// The other half, so the fix above cannot be "always claim nothing": a readable with-skill answer
    /// still reports the skill it names.
    @Test("A readable with-skill answer still reports the skill it names")
    func readableWithSkillStillFires() throws {
        let answer = ReplayAdapter.Answer(baseline: false, marker: nil, query: "q", firedSkills: ["tidy-notes"])
        let trace = try ReplayAdapter().parseTrace(
            RawTrace(harness: "replay", raw: ReplayAdapter.encode(answer)))
        #expect(trace.skillInvocations.map(\.skill) == ["tidy-notes"])
    }
}
