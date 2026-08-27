import Testing
import Foundation
@testable import EDDCore

@Suite("JSON envelope")
struct JSONEnvelopeTests {
    @Test("Root payload encodes deterministically with a schema field (golden)")
    func rootGolden() throws {
        let info = RootInfo(
            skilletVersion: "1.2.3",
            project: ProjectContext(root: "/repo", discoveredVia: .gitBoundary, cwd: "/repo/sub", configPath: nil),
            loop: [LoopVerb(name: "run", summary: "measure")]
        )
        let json = try SkilletJSON.encode(info)
        #expect(json == #"{"loop":[{"name":"run","summary":"measure"}],"project":{"cwd":"/repo/sub","discovered_via":"git_boundary","root":"/repo"},"schema":"skillet.root/1","skillet_version":"1.2.3"}"#)
    }

    @Test("nil optionals are omitted, not encoded as null")
    func omitsNilOptionals() throws {
        let info = RootInfo(
            skilletVersion: "0",
            project: ProjectContext(root: nil, discoveredVia: .none, cwd: "/x", configPath: nil),
            loop: []
        )
        let json = try SkilletJSON.encode(info)
        #expect(!json.contains(#""root":"#)) // the `root` key is omitted ("root" still appears in the schema value)
        #expect(!json.contains("config_path"))
        #expect(!json.contains("null"))
        #expect(json.contains(#""discovered_via":"none""#))
    }

    @Test("Encoding is stable across runs")
    func deterministic() throws {
        let info = RootInfo(
            skilletVersion: "9",
            project: ProjectContext(root: "/a", discoveredVia: .skilletYAML, cwd: "/a", configPath: "/a/skillet.yaml"),
            loop: LoopVerb.canonical
        )
        #expect(try SkilletJSON.encode(info) == (try SkilletJSON.encode(info)))
    }

    @Test("Error payload carries schema, numeric code, and kind")
    func errorPayload() throws {
        let json = try SkilletJSON.encode(ErrorPayload(.directoryNotFound(path: "/no/such")))
        #expect(json.contains(#""schema":"skillet.error/1""#))
        #expect(json.contains(#""code":3"#))
        #expect(json.contains(#""kind":"directory_not_found""#))
    }
}

/// **What this tool writes, it can read back.**
///
/// The published output carries two names that spell a digit as a word — `pass_1` and `pass_1_evals` —
/// because the measure they name is written that way in the literature. The standard rule for turning a
/// published name back into a Swift one mangles those into `pass1` and `pass1Evals`, which match nothing,
/// so the whole payload failed to read back: the text written out was correct and reading it returned
/// nothing at all. Nothing caught it because every test until now only checked what was *written*.
@Suite("The published output can be read back")
struct PublishedKeysRoundTripTests {
    /// **The written-out rule must agree with the built-in one everywhere else.** Replacing the built-in
    /// conversion means re-implementing it, and an accidental difference would silently stop some other
    /// field being read. Every published name this project uses is compared against what the built-in rule
    /// produces — except the two that carry a digit, which is the whole reason for the replacement.
    @Test("The replacement agrees with the standard rule on every ordinary name", arguments: [
        "skill", "observed_k", "pass_k", "measurable", "evals", "passed", "flaky", "failed", "trigger",
        "ab", "ungraded", "cost_unreadable", "eval_id", "perfect_passes", "mean_pass_rate", "run_number",
        "total_tokens", "input_uncached_tokens", "input_cache_read_tokens", "skill_invocations",
        "workspace_diff", "harness_version", "started_at", "usage_state", "files_touched", "turn_index"
    ])
    func agreesWithTheStandardRule(published: String) throws {
        struct Probe: Decodable {
            let seen: [String]
            init(from decoder: Decoder) throws {
                seen = try decoder.container(keyedBy: DynamicCodingKey.self).allKeys.map(\.stringValue)
            }
        }
        let json = Data("{\"\(published)\":1}".utf8)
        let standard = JSONDecoder(); standard.keyDecodingStrategy = .convertFromSnakeCase
        let expected = try standard.decode(Probe.self, from: json).seen
        #expect(SkilletJSON.swiftName(forPublishedKey: published) == expected[0],
                "'\(published)' must convert exactly as the standard rule does")
    }

    @Test("A name spelling a digit as a word is handed back exactly as published",
          arguments: ["pass_1", "pass_1_evals"])
    func digitNamesArePassedThrough(published: String) {
        #expect(SkilletJSON.swiftName(forPublishedKey: published) == published,
                "the standard rule would mangle this one, which is why it is written out")
    }
}

/// **A report this tool writes can be read back, and says the same thing.**
///
/// Nothing checked this before: every test verified what was *written*. The published output could not be
/// read back at all — the type was not decodable, and two of its published names could not be matched by
/// the shared reader even if it had been. So the machine-readable contract was one-way, which defeats the
/// purpose of publishing one.
@Suite("A published report reads back as what was written")
struct ReportRoundTripTests {
    private func report() throws -> RunReport {
        try RunReport(skill: "demo", results: [
            EvalResult(evalId: "a", trials: [TrialResult(exit: .passed, verdicts: [
                Verdict(criterion: "c", passed: true, rationale: "", judgeId: "t", model: "m", judgePromptVersion: "1")])]),
            EvalResult(evalId: "b", trials: [TrialResult(exit: .error, verdicts: [])])
        ])
    }

    @Test("Everything published survives the round trip")
    func survivesTheRoundTrip() throws {
        let original = try report()
        let text = try SkilletJSON.encode(original)
        let back = try SkilletJSON.decode(RunReport.self, from: text)
        #expect(back == original, "what was written must read back as itself")
    }

    /// **The before-and-after comparison is rebuilt too, not believed.** The report's own figures were
    /// re-derived on read while the comparison block beside them was taken from the text as-is — so a
    /// published report could claim a skill fixed ninety-nine checks while the rows next to it showed one.
    /// Measured before this: tampering with that tally returned the tampered number.
    @Test("A tampered comparison loses to the rows it sits next to")
    func comparisonIsRebuilt() throws {
        let verdict = { (ok: Bool) in Verdict(criterion: "c", passed: ok, rationale: "",
                                              judgeId: "t", model: "m", judgePromptVersion: "1") }
        let original = try RunReport(
            skill: "demo",
            results: [EvalResult(evalId: "a", trials: [TrialResult(exit: .passed, verdicts: [verdict(true)])])],
            baseline: [EvalResult(evalId: "a", trials: [TrialResult(exit: .failed, verdicts: [verdict(false)])])])
        let tampered = try SkilletJSON.encode(original)
            .replacingOccurrences(of: "\"flips_up\":1", with: "\"flips_up\":99")
            .replacingOccurrences(of: "\"flipsUp\":1", with: "\"flipsUp\":99")
        let back = try SkilletJSON.decode(RunReport.self, from: tampered)
        #expect(back.ab?.flipsUp == 1, "one check went from failing to passing, whatever the text claims")
        #expect(back.ab?.flipsUp != 99)
        #expect(back.ab?.pairedMeanDelta == original.ab?.pairedMeanDelta, "and the average with it")
    }

    /// **A repeated check name is refused, as it is by both other ways of building a report.**
    /// Reading a published one accepted it and worked out a score from the repeated rows, making the
    /// published format the most permissive of the three when it exists to mirror them.
    @Test("A report naming the same check twice is refused")
    func repeatedNameIsRefused() throws {
        let original = try RunReport(skill: "demo", results: [
            EvalResult(evalId: "a", trials: [TrialResult(exit: .passed, verdicts: [
                Verdict(criterion: "c", passed: true, rationale: "", judgeId: "t", model: "m", judgePromptVersion: "1")])])])
        let doubled = try SkilletJSON.encode(original).replacingOccurrences(
            of: "\"evals\":[",
            with: "\"evals\":[{\"id\":\"a\",\"passes\":0,\"recorded\":1,\"status\":\"fail\"},")
        #expect(throws: (any Error).self) { try SkilletJSON.decode(RunReport.self, from: doubled) }
    }

    /// The figures are worked out from the rows, so text claiming otherwise must not win — the same rule
    /// the proving command's report was given.
    @Test("Text claiming figures its own rows contradict does not win")
    func derivedFiguresAreRebuilt() throws {
        let original = try report()
        var text = try SkilletJSON.encode(original)
        text = text.replacingOccurrences(of: "\"passed\":1", with: "\"passed\":99")
            .replacingOccurrences(of: "\"observed_k\":0", with: "\"observed_k\":99")
        let back = try SkilletJSON.decode(RunReport.self, from: text)
        // Compared against what the rows actually support, rather than a number written here — the rows
        // are the evidence, and one of these checks never produced a result.
        #expect(back.passed == original.passed, "one check passed, whatever the text claims")
        #expect(back.observedK == original.observedK, "and the repeats figure comes from the rows too")
        #expect(back.passed != 99, "the text's claim must not be the answer")
    }
}
