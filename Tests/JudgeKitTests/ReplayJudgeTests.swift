import Testing
import Foundation
import EDDCore
import TraceKit
@testable import JudgeKit


/// **The version label is recovered exactly, not merely present.**
///
/// To test this tool without paying a model, a stand-in answers instead, and tells two versions of the
/// same skill apart using a short label written in the skill's own file. The stand-in wraps that label
/// into the answer as `done [label]`; the part that decides whether an answer met an expectation recovers
/// it as everything between the first `" ["` and the final `"]"`, and looks up the recorded verdict under
/// it. A label that came back changed would grade against a different entry, silently — which is how an
/// identical edit was once declared proven under one label and blocked under another.
///
/// **The gap this closes is what was being asserted.** A test already checks that the label reaches the
/// answer text. Reaching it is not the same as coming back out of it, and checking the first while
/// meaning the second is the shape that has hidden three separate faults in this project.
@Suite("A version label comes back exactly as it went in")
struct MarkerRecoveryTests {
    /// The awkward values are the point: brackets are the framing, so a label made of them is the case
    /// where a careless reader would take the wrong span.
    @Test("Labels made of the framing characters still come back whole", arguments: [
        "v[1] release", "]", "a]b[c", "[[[", "x [y", "with ] and [", "trailing ]]]", "後方互換", ""
    ])
    func awkwardLabelsRecover(label: String) {
        // Exactly what the stand-in produces: the fixed answer text, then the label in brackets.
        #expect(ReplayJudge.marker(in: "done [\(label)]") == label)
    }

    /// An answer with no label at all yields none, rather than a fragment of the text.
    @Test("An answer carrying no label yields none", arguments: ["done", "done]", "[done]", ""])
    func noLabelYieldsNone(text: String) {
        #expect(ReplayJudge.marker(in: text) == nil || text.hasPrefix("done ["))
    }

    /// **The consequence, not just the spelling.** A recorded verdict is stored under the label, so a
    /// label that came back changed would find the wrong entry — or none, and fall through to a default.
    @Test("A recorded verdict is found under an awkward label")
    func verdictFoundUnderAwkwardLabel() async throws {
        let judge = ReplayJudge(["did the thing @ v[1] release": true], defaultPass: false)
        let anySession = Trace(harness: "t", harnessVersion: "1",
                               startedAt: Date(timeIntervalSince1970: 0),
                               endedAt: Date(timeIntervalSince1970: 1),
                               turns: [], skillInvocations: [], workspaceDiff: WorkspaceDiff(), usage: nil)
        let evidence = JudgeEvidence(responseText: "done [v[1] release]", trace: anySession,
                                     workspaceListing: [], fileContents: nil)
        let verdict = try await judge.verdict(for: "did the thing", evidence: evidence)
        #expect(verdict.passed, "the recorded answer for this label must be the one that is found")
    }
}

/// **A marker containing brackets must survive, which is why the marker is read from the FIRST `" ["`.**
///
/// A review asked whether the marker could be cut short by brackets inside it. Measured: it cannot — the
/// marker is read from the first `" ["` to the final `]`, so anything at all between those, brackets
/// included, comes back whole. That includes `v[1] release`, the name in the bug this framing was
/// introduced to fix.
///
/// **This is pinned because the obvious "hardening" would break it.** Reading from the *last* `" ["`
/// instead would protect against brackets in the text before the marker — which is already prevented, by
/// tests on the only thing that writes that text — while silently truncating every marker that contains
/// `" ["`, which works today. The safe-looking change is the harmful one, so the property that makes the
/// current direction correct is recorded here rather than left to be re-derived.
@Suite("A marker keeps its brackets")
struct MarkerBracketTests {
    @Test("Whatever the marker contains comes back whole",
          arguments: ["v1", "v[1] release", "a]b", "a [b", "]", "[[", "[]", ""])
    func markerSurvivesBrackets(marker: String) {
        // Exactly how the stand-in writes it: the answer text, a space, then the marker in brackets.
        #expect(ReplayJudge.marker(in: "done [\(marker)]") == marker)
    }

    @Test("Text with no marker yields none")
    func noMarkerYieldsNothing() {
        #expect(ReplayJudge.marker(in: "done") == nil)
        #expect(ReplayJudge.marker(in: "done]") == nil)
    }
}
