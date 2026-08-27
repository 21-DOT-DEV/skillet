import Testing
import Foundation
@testable import EDDCore

/// **What the saved results file says about tokens.**
///
/// A *token* is the unit a model charges and reasons in. The file records one block per run — the run
/// with the skill available and the run deliberately without it — plus a third block reporting how the
/// two differ. Until now all three carried invented zeros for tokens, because nothing counted them: a
/// zero that reads as "measured, and it came to nothing" rather than "nobody counted".
@Suite("The results file reports token counts only where something counted them")
struct TokenRecordTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")

    private func verdict(_ passed: Bool) -> Verdict {
        Verdict(criterion: "c", passed: passed, rationale: "r",
                judgeId: "j", model: "m", judgePromptVersion: "v")
    }

    private func trial(_ passed: Bool, tokens: TokenCounts?) -> TrialResult {
        TrialResult(exit: .passed, verdicts: [verdict(passed)], durationSeconds: 1, tokens: tokens)
    }

    private func counts(_ n: Int) throws -> TokenCounts {
        try #require(TokenCounts(uncachedInput: n, cacheRead: n * 2, cacheWrite: n / 2, output: n * 3))
    }

    private func file(withTokens: TokenCounts?, baseTokens: TokenCounts?) throws -> BenchmarkFile {
        let withArm = [EvalResult(evalId: "a", trials: [trial(true, tokens: withTokens)])]
        let baseline = [EvalResult(evalId: "a", trials: [trial(false, tokens: baseTokens)])]
        return try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, baseline: baseline), evals: withArm),
            baseline: baseline, trigger: nil, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
    }

    /// **No field is called `input_tokens`.** Two published conventions give that one name opposite
    /// meanings — the input that missed the cache, and the whole input regardless — so a reader of a
    /// single field under that name has a 50/50 chance of being wrong by the size of the cached context.
    /// Every field is named for exactly what it holds, and the roll-up carries the unambiguous name.
    @Test("A run that counted tokens reports the roll-up and each part, under unambiguous names")
    func partsAndRollUp() throws {
        let record = try file(withTokens: try counts(100), baseTokens: nil)
        let block = try #require(record.runSummary?["with_skill"]?.objectValue?["tokens"]?.objectValue)
        #expect(block["total_tokens"] == .number(650), "100 + 200 + 50 + 300, each counted once")
        #expect(block["input_uncached_tokens"] == .number(100))
        #expect(block["input_cache_read_tokens"] == .number(200))
        #expect(block["input_cache_write_tokens"] == .number(50))
        #expect(block["output_tokens"] == .number(300))
        #expect(block["input_tokens"] == nil,
                "that name means two different things, so nothing may be published under it")
    }

    @Test("A run that counted nothing says nothing about tokens")
    func silentWhenUncounted() throws {
        let record = try file(withTokens: nil, baseTokens: nil)
        #expect(record.runSummary?["with_skill"]?.objectValue?["tokens"] == nil)
        #expect(record.runSummary?["without_skill"]?.objectValue?["tokens"] == nil)
        #expect(record.runSummary?["delta"]?.objectValue?["total_tokens_per_attempt"] == nil)
    }

    /// A difference needs two measurements. One run counting and the other not is not a difference of
    /// "everything the counted one used" — it is no difference at all, the same rule the elapsed-time
    /// entry beside it already follows.
    @Test("A difference appears only when both runs counted")
    func differenceNeedsBothSides() throws {
        let oneSided = try file(withTokens: try counts(100), baseTokens: nil)
        #expect(oneSided.runSummary?["delta"]?.objectValue?["total_tokens_per_attempt"] == nil,
                "only one run counted, so there is no difference to state")

        let bothSides = try file(withTokens: try counts(100), baseTokens: try counts(20))
        #expect(bothSides.runSummary?["delta"]?.objectValue?["total_tokens_per_attempt"] == .string("+520.00"),
                "650 read with the skill against 130 without it")
    }

    /// The difference goes the other way too — a skill that makes the model read *less* is reported as
    /// less, not as an unsigned size.
    @Test("A skill that reduces what the model reads reports a negative difference")
    func negativeDifference() throws {
        let record = try file(withTokens: try counts(20), baseTokens: try counts(100))
        #expect(record.runSummary?["delta"]?.objectValue?["total_tokens_per_attempt"] == .string("-520.00"))
    }

    /// Only the roll-up gets a difference. The cached-versus-fresh split moves on whether the provider
    /// happened to have seen a similar request recently, so publishing *its* difference under a heading
    /// that reads as "what the skill did" would state timing luck as an effect of the skill.
    @Test("The cached-versus-fresh split is reported per run, never as a difference")
    func splitNotDifferenced() throws {
        let record = try file(withTokens: try counts(100), baseTokens: try counts(20))
        let delta = try #require(record.runSummary?["delta"]?.objectValue)
        #expect(delta["total_tokens_per_attempt"] != nil)
        for part in ["input_uncached_tokens", "input_cache_read_tokens",
                     "input_cache_write_tokens", "output_tokens"] {
            #expect(delta[part] == nil, "\(part) moves on cache warmth, not on the skill")
        }
    }
}

@Suite("A token count's roll-up is its parts")
struct TokenCountsArithmeticTests {
    @Test("The total is everything read and written, each part counted once")
    func totalIsTheSum() throws {
        let counts = try #require(TokenCounts(uncachedInput: 5, cacheRead: 128_955,
                                              cacheWrite: 1_253, output: 100))
        #expect(counts.total == 130_313)
    }

    /// **A count below none is refused where the value is made.** These count things a model read and
    /// wrote; none can be negative, and one arriving from a provider's reply or a test fixture would
    /// otherwise flow into the totals written into the saved results file.
    @Test("A count below none is refused", arguments: [
        (-1, 0, 0, 0), (0, -1, 0, 0), (0, 0, -1, 0), (0, 0, 0, -1), (-1, -1, -1, -1)
    ])
    func negativeCountRefused(uncached: Int, read: Int, write: Int, output: Int) {
        #expect(TokenCounts(uncachedInput: uncached, cacheRead: read,
                            cacheWrite: write, output: output) == nil)
    }

    /// **Reading one back from a file refuses the same counts the constructor does.** The refusal above
    /// was settled where a value is built in code; reading one back from a saved file builds a value too,
    /// and it accepted straight back in what the constructor had just rejected — so the type could hold,
    /// by way of a file, a value nobody could write in code. Reading an object back is a second
    /// constructor and has to establish the same invariants.
    @Test("A count below none in a file is refused when it is read back", arguments: [
        ("input_uncached_tokens", "input_uncached_tokens"), ("input_cache_read_tokens", "input_cache_read_tokens"),
        ("input_cache_write_tokens", "input_cache_write_tokens"), ("output_tokens", "output_tokens")
    ])
    func negativeCountInFileRefused(field: String, named: String) throws {
        var object: [String: Int] = ["input_uncached_tokens": 5, "input_cache_read_tokens": 5,
                                     "input_cache_write_tokens": 5, "output_tokens": 5]
        object[field] = -3
        let data = try JSONSerialization.data(withJSONObject: object)
        let reader = JSONDecoder(); reader.keyDecodingStrategy = .convertFromSnakeCase
        do {
            _ = try reader.decode(TokenCounts.self, from: data)
            Issue.record("a count of -3 in \(field) was read back instead of being refused")
        } catch let DecodingError.dataCorrupted(context) {
            // Names the field in the spelling the file uses, and the value that was actually there —
            // so the reader can find it without knowing how this program spells its own fields.
            #expect(context.debugDescription.contains(named))
            #expect(context.debugDescription.contains("-3"))
        }
    }

    @Test("Counts that are all possible are read back unchanged")
    func realCountsSurviveTheRoundTrip() throws {
        let counts = try #require(TokenCounts(uncachedInput: 5, cacheRead: 0, cacheWrite: 1_253, output: 100))
        let writer = JSONEncoder(); writer.keyEncodingStrategy = .convertToSnakeCase
        let reader = JSONDecoder(); reader.keyDecodingStrategy = .convertFromSnakeCase
        #expect(try reader.decode(TokenCounts.self, from: writer.encode(counts)) == counts)
    }

    /// **A count too large to write down exactly is refused where the value is made.**
    ///
    /// These numbers are written into the saved results file as JSON, where a number is held as a double.
    /// Above the largest whole number a double holds exactly, the value silently changes on the way
    /// through — so the file would state a count that is not the one that was counted. The JSON standard
    /// names this same range as the one where every reader agrees on the value.
    ///
    /// **The same rule also removes a way the program could stop dead.** Adding four counts up could
    /// exceed what a whole number holds, which halts the program rather than wrapping round: measured, a
    /// run declaring counts near that ceiling parked while writing them out and never returned, leaving
    /// nothing behind. Four values under this ceiling cannot get near it.
    /// **Plain numbers, not ones worked out from the ceiling.** Working them out from the ceiling means
    /// the test moves with it, so it stops pinning the thing it exists to pin — and worse, at the largest
    /// whole number the expression `ceiling + 1` overflows while the list of cases is being built, which
    /// stops the process before any test runs rather than failing one.
    @Test("A count too large to record exactly is refused", arguments: [
        9_007_199_254_740_992,          // 2^53 — one above the largest that survives being written down
        9_007_199_254_740_993,
        1 << 62
    ])
    func unrecordableCountRefused(value: Int) {
        #expect(TokenCounts(uncachedInput: value, output: 0) == nil)
        #expect(TokenCounts(uncachedInput: 0, output: value) == nil)
    }

    /// **Written out rather than worked out from the ceiling.** These four add to one more than the
    /// largest recordable total, using plain numbers — derive them from the ceiling instead and they move
    /// with it, so a test meant to pin the ceiling silently stops testing it if the ceiling is changed.
    /// Found the hard way: an earlier version of this test moved with the ceiling and, at the largest
    /// whole number, made the sum overflow instead, which stops the process rather than failing the test.
    @Test("Four counts that only together exceed what can be recorded are refused")
    func unrecordableTotalRefused() {
        let quarterOfTheCeiling = 2_251_799_813_685_248        // 2^51 — four of these make 2^53
        #expect(TokenCounts(uncachedInput: quarterOfTheCeiling, cacheRead: quarterOfTheCeiling,
                            cacheWrite: quarterOfTheCeiling, output: quarterOfTheCeiling) == nil,
                "2^53 is one above the largest total that survives being written down")
    }

    @Test("The largest recordable total is accepted and survives being written down")
    func largestRecordableSurvives() throws {
        let counts = try #require(TokenCounts(uncachedInput: TokenCounts.largestExact, output: 0))
        #expect(counts.total == TokenCounts.largestExact)
        // The value as the results file would hold it must be the value that was counted.
        let written = try #require(counts.jsonObject["total_tokens"]?.numberValue)
        #expect(Int(exactly: written.rounded()) == TokenCounts.largestExact)
    }

    /// Two totals that are each recordable can add to one that is not, which is why adding can answer
    /// "no" even though every count going in was fine.
    @Test("Adding two recordable counts into an unrecordable total is refused")
    func additionRefusesAnUnrecordableTotal() throws {
        let half = try #require(TokenCounts(uncachedInput: 4_503_599_627_370_496, output: 0))   // 2^52
        let sum: TokenCounts? = half + half
        #expect(sum == nil)
    }

    /// **The signed number written into the record is read back as the same number.**
    ///
    /// The difference between the two arms is written as text like `+0.50` and parsed back. Both ends are
    /// fixed to a neutral convention — the writer names it explicitly, and Swift's text-to-number
    /// conversion is always the neutral one, never the machine's regional setting: `Double("0,50")`
    /// yields nothing. The two are independent decisions that must agree, so the agreement is pinned here
    /// rather than left to hold by luck if either end is changed.
    @Test("A signed difference survives being written and read back",
          arguments: [0.5, -0.5, 0.0, 1234.25, -0.01])
    func signedDifferenceRoundTrips(value: Double) throws {
        let written = String(format: "%+.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        #expect(Double(written) == (value * 100).rounded() / 100)
    }

    @Test("A number written the way some regions do is refused rather than misread")
    func regionalNumberRefused() {
        #expect(Double("0,50") == nil, "reading this as a half would silently change a measurement")
    }

    @Test("Counts of none are a real measurement and are accepted")
    func zeroCountsAccepted() throws {
        let counts = try #require(TokenCounts(uncachedInput: 0, cacheRead: 0, cacheWrite: 0, output: 0))
        #expect(counts.total == 0)
    }

    @Test("Adding two attempts adds each kind separately")
    func additionIsPerKind() throws {
        let one = try #require(TokenCounts(uncachedInput: 1, cacheRead: 2, cacheWrite: 3, output: 4))
        let ten = try #require(TokenCounts(uncachedInput: 10, cacheRead: 20, cacheWrite: 30, output: 40))
        let sum: TokenCounts? = one + ten
        let both = try #require(sum)
        #expect(both == (try #require(TokenCounts(uncachedInput: 11, cacheRead: 22,
                                                  cacheWrite: 33, output: 44))))
        #expect(both.total == 110)
    }
}

/// **The same four numbers are called the same thing in every file that carries them.**
///
/// A run leaves behind a diagnostic file per attempt and a saved results file for the run. Someone
/// checking why a figure looks wrong reads them side by side. They used to use different vocabularies for
/// the same quantities — one said `cache_read`, the other `input_cache_read_tokens` — so a reader had to
/// know the two meant the same thing. A test compares them rather than trusting them to stay aligned.
@Suite("Token counts are named identically wherever they are written")
struct TokenVocabularyTests {
    /// The figures from the filed double-counting report, built once. Made through the refusing
    /// constructor like every other, so the fixture cannot hold a value the type would reject.
    private func sample() throws -> TokenCounts {
        try #require(TokenCounts(uncachedInput: 5, cacheRead: 128_955, cacheWrite: 1_253, output: 100))
    }

    private func encodedNames() throws -> Set<String> {
        let data = try SkilletJSON.encoder().encode(try sample())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    @Test("The diagnostic file and the results file use one set of names")
    func oneVocabulary() throws {
        let names = try sample().jsonObject.keys
        #expect(try encodedNames() == Set(names))
    }

    @Test("Those names are the unambiguous ones, and none is the name that means two things")
    func namesAreUnambiguous() throws {
        #expect(try encodedNames() == ["total_tokens", "input_uncached_tokens", "input_cache_read_tokens",
                                       "input_cache_write_tokens", "output_tokens"])
        #expect(!(try encodedNames().contains("input_tokens")),
                "one convention means the uncached part by that name and another means the whole input")
    }

    /// **The roll-up is written for a reader and recomputed on the way back in.** Adding these four up is
    /// exactly what people get wrong, so a file states the answer; but a file whose stated roll-up
    /// disagrees with its own parts is resolved in favour of the parts rather than believed.
    @Test("A stated roll-up that contradicts its parts is ignored in favour of the parts")
    func rollUpIsRecomputedOnRead() throws {
        let tampered = #"{"total_tokens":999999,"input_uncached_tokens":5,"input_cache_read_tokens":128955,"input_cache_write_tokens":1253,"output_tokens":100}"#
        let decoded = try SkilletJSON.decoder().decode(TokenCounts.self, from: Data(tampered.utf8))
        #expect(decoded.total == 130_313, "the parts are the truth; the stated roll-up is a convenience")
        let expected = try sample()
        #expect(decoded == expected)
    }

    @Test("A run's counts survive being written and read back")
    func roundTrips() throws {
        let written = try SkilletJSON.encoder().encode(try sample())
        let expected = try sample()
        #expect(try SkilletJSON.decoder().decode(TokenCounts.self, from: written) == expected)
    }
}

/// **The check that asks whether a model reaches for the right skill records no score when it never ran.**
///
/// That check hands a model a shelf of skills and a prompt, and asks which it reaches for. If it recorded
/// no attempts at all — nothing was tried — a score of zero reads as "we asked, and the skill was never
/// reached for", the most damning possible reading of the skill being tested. The two other summary
/// blocks in the same file were given this rule a round earlier and this one was missed.
@Suite("An untried routing check records no score")
struct UntriedRoutingScoreTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")

    private func file(routingTrials: [TriggerTrialResult], repeats: Int) throws -> BenchmarkFile {
        let withArm = [EvalResult(evalId: "a", trials: [TrialResult(
            exit: .passed,
            verdicts: [Verdict(criterion: "c", passed: true, rationale: "r",
                               judgeId: "j", model: "m", judgePromptVersion: "v")],
            durationSeconds: 1)])]
        let routing = [TriggerEvalResult(evalId: "t", query: "q", shouldTrigger: true, trials: routingTrials)]
        return try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, trigger: routing), evals: withArm),
            baseline: nil, trigger: routing, harness: "replay", k: repeats,
            provenance: provenance, preserving: nil)
    }

    @Test("Nothing tried ⇒ no score recorded")
    func nothingTriedRecordsNoScore() throws {
        let record = try file(routingTrials: [], repeats: 0)
        #expect(record.runSummary?["trigger"]?.objectValue?["pass_rate"] == nil,
                "nothing was tried, so there is no score to state")
    }

    /// The other half, so the guard cannot be satisfied by never recording a score: a check that ran and
    /// found the skill was not reached for records that real zero.
    @Test("Tried, and the skill was not reached for ⇒ the real zero is recorded")
    func genuineMissRecordsZero() throws {
        let record = try file(routingTrials: [TriggerTrialResult(exit: .passed, firedTarget: false, firedOther: [])],
                              repeats: 1)
        #expect(record.runSummary?["trigger"]?.objectValue?["pass_rate"]?.objectValue?["mean"] == .number(0),
                "it was asked and the answer was no, which is a measurement")
    }

    @Test("Tried, and the skill was reached for ⇒ recorded as such")
    func genuineHitRecorded() throws {
        let record = try file(routingTrials: [TriggerTrialResult(exit: .passed, firedTarget: true, firedOther: [])],
                              repeats: 1)
        #expect(record.runSummary?["trigger"]?.objectValue?["pass_rate"]?.objectValue?["mean"] == .number(1))
    }
}

/// **A run whose every attempt was thrown out has no score, and must not record one.**
///
/// An attempt is disqualified when a skill was used in the run that was supposed to be without it — that
/// attempt measures nothing, so it is never graded. When *every* attempt goes that way, the run measured
/// nothing at all. Recording a score of zero there is indistinguishable from a run that genuinely got
/// everything wrong, and it reads as the most flattering possible result for the skill being tested:
/// without it, nothing worked. The command does refuse such a comparison — but the file is written before
/// the refusal and outlives it, so anything reading the file later saw a fabricated zero unmarked.
@Suite("An arm that measured nothing records no score")
struct UnmeasuredArmScoreTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")

    private func trial(_ passed: Bool, exit: TrialExit = .passed) -> TrialResult {
        TrialResult(exit: exit,
                    verdicts: exit == .polluted ? [] : [Verdict(criterion: "c", passed: passed, rationale: "r",
                                                                judgeId: "j", model: "m", judgePromptVersion: "v")],
                    durationSeconds: 1)
    }

    private func file(baselineTrials: [TrialResult]) throws -> BenchmarkFile {
        let withArm = [EvalResult(evalId: "a", trials: [trial(true)])]
        let baseline = [EvalResult(evalId: "a", trials: baselineTrials)]
        return try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, baseline: baseline), evals: withArm),
            baseline: baseline, trigger: nil, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
    }

    @Test("Every attempt disqualified ⇒ no score recorded for that run")
    func allDisqualifiedRecordsNoScore() throws {
        let record = try file(baselineTrials: [trial(false, exit: .polluted), trial(false, exit: .polluted)])
        // **The rule is "no score is stated", which holds whether or not the arm appears.** These attempts
        // carry no timing and no cost either, so there is nothing at all to put in the arm and it is left
        // out entirely. A real disqualified attempt did run and did cost something, so its arm would still
        // appear with only the score missing. Asserting the rule rather than the shape keeps this true in
        // both cases, and still fails if a score is ever written here.
        #expect(record.runSummary?["without_skill"]?.objectValue?["pass_rate"] == nil,
                "nothing was graded, so there is no score to state")
    }

    /// The other half, so the guard cannot be satisfied by never recording a score: a run that genuinely
    /// scored zero still records that zero, because it is a real result.
    /// **The per-test row states no result either, not just the run's summary.** An entry saying a test
    /// scored zero is indistinguishable from one that ran and got everything wrong, and reads as the most
    /// flattering possible result for the skill: without it, this did not work. The counts beside it stay,
    /// because they are facts — nothing ran, nothing passed, this many attempts were thrown out.
    @Test("A test whose every attempt was thrown out states no result in its own row")
    func disqualifiedRowStatesNoResult() throws {
        let record = try file(baselineTrials: [trial(false, exit: .polluted), trial(false, exit: .polluted)])
        let rows = record.fields["consistency"]?.objectValue?["per_eval"]?.arrayValue ?? []
        let row = try #require(rows.first { $0.objectValue?["arm"]?.stringValue == "baseline" }?.objectValue)
        #expect(row["pass_power_k"] == nil, "nothing was graded, so it neither passed nor failed")
        #expect(row["mean_pass_rate"] == nil, "and there is no score to average")
        #expect(row["runs"] == .number(0), "the facts stay: nothing ran")
        #expect(row["polluted"] == .number(2), "and this many attempts were thrown out")
    }

    /// The other half: a test that ran and failed everything still records that, because it is a result.
    /// **The same rule in all three kinds of row, which is what it was missing.** A run's summary already
    /// withheld its score when nothing was measured, while the rows underneath still said a test had
    /// failed — one file saying both things at once. The counts stay, because they are facts; the three
    /// conclusions drawn from attempts are withheld when there were none.
    @Test("A test that recorded no attempts states no verdict, in every kind of row")
    func noAttemptsMeansNoVerdictAnywhere() throws {
        let withArm = [EvalResult(evalId: "a", trials: [])]
        let routing = [TriggerEvalResult(evalId: "t", query: "q", shouldTrigger: true, trials: [])]
        let record = try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, trigger: routing), evals: withArm),
            baseline: nil, trigger: routing, harness: "replay", k: 0,
            provenance: provenance, preserving: nil)
        let rows = record.fields["consistency"]?.objectValue?["per_eval"]?.arrayValue ?? []
        #expect(rows.count == 2, "both rows are still written — the tests exist")
        for row in rows {
            let entry = try #require(row.objectValue)
            let which = entry["axis"]?.stringValue ?? "behaviour"
            #expect(entry["pass_power_k"] == nil, "\(which): nothing ran, so it neither passed nor failed")
            #expect(entry["flaky"] == nil, "\(which): nothing ran, so it cannot be called unreliable")
            #expect(entry["mean_pass_rate"] == nil, "\(which): there is no score to average")
            #expect(entry["runs"] == .number(0), "\(which): the fact that nothing ran stays")
        }
    }

    /// The other half, so the rule cannot be satisfied by never stating a verdict.
    @Test("A test that did run states its verdict, in every kind of row")
    func attemptsMeanVerdictsAnywhere() throws {
        let attempt = TrialResult(
            exit: .passed,
            verdicts: [Verdict(criterion: "c", passed: true, rationale: "r",
                               judgeId: "j", model: "m", judgePromptVersion: "v")],
            durationSeconds: 1)
        let withArm = [EvalResult(evalId: "a", trials: [attempt])]
        let routing = [TriggerEvalResult(evalId: "t", query: "q", shouldTrigger: true,
                                         trials: [TriggerTrialResult(exit: .passed, firedTarget: true, firedOther: [])])]
        let record = try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, trigger: routing), evals: withArm),
            baseline: nil, trigger: routing, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
        let rows = record.fields["consistency"]?.objectValue?["per_eval"]?.arrayValue ?? []
        for row in rows {
            let entry = try #require(row.objectValue)
            #expect(entry["pass_power_k"] == .number(1))
            #expect(entry["mean_pass_rate"] != nil)
        }
    }

    @Test("A test that ran and failed everything still records the failure in its row")
    func gradedFailureStillStatesResult() throws {
        let record = try file(baselineTrials: [trial(false), trial(false)])
        let rows = record.fields["consistency"]?.objectValue?["per_eval"]?.arrayValue ?? []
        let row = try #require(rows.first { $0.objectValue?["arm"]?.stringValue == "baseline" }?.objectValue)
        #expect(row["pass_power_k"] == .number(0), "graded twice and failed both times is a real result")
        #expect(row["mean_pass_rate"] == .number(0))
    }

    @Test("A run that was graded and scored zero still records the zero")
    func genuineZeroIsRecorded() throws {
        let record = try file(baselineTrials: [trial(false), trial(false)])
        let arm = try #require(record.runSummary?["without_skill"]?.objectValue)
        #expect(arm["pass_rate"]?.objectValue?["mean"] == .number(0),
                "graded twice and failed both times is a measurement, and it measures zero")
    }

    /// One disqualified attempt among graded ones leaves the graded ones scored — the run is not written
    /// off because part of it was.
    @Test("A run with some attempts disqualified is scored on the ones that were graded")
    func partiallyDisqualifiedIsScoredOnTheRest() throws {
        let record = try file(baselineTrials: [trial(true), trial(false, exit: .polluted)])
        let arm = try #require(record.runSummary?["without_skill"]?.objectValue)
        #expect(arm["pass_rate"]?.objectValue?["mean"] == .number(1),
                "the one graded attempt passed; the disqualified one is not a zero dragging it down")
    }
}

/// **Adding up nothing gives nothing, not a row of zeros.**
///
/// The helper that totals several attempts' token counts starts from the first item, so handing it an
/// empty list stops the program where it stands. The place that calls it checks first, so that cannot
/// happen today — but the obvious repair, starting the sum at zero, would answer an empty list with a
/// full set of zeros, which is the invented measurement this file spent a round removing. An empty list
/// is the ordinary state of every run made without a real model, so it is answered, not ruled out.
@Suite("Totalling no attempts reports nothing")
struct EmptyTokenTotalTests {
    @Test("Nothing to add up is reported as nothing")
    func emptyReportsNothing() {
        #expect(BenchmarkFile.tokenBlock([]) == nil, "and specifically not a set of zeros")
    }

    @Test("One attempt totals to itself, and several add up")
    func nonEmptyStillTotals() throws {
        let one = try #require(TokenCounts(uncachedInput: 1, cacheRead: 2, cacheWrite: 3, output: 4))
        #expect(BenchmarkFile.tokenBlock([one])?.objectValue?["total_tokens"] == .number(10))
        #expect(BenchmarkFile.tokenBlock([one, one])?.objectValue?["total_tokens"] == .number(20))
    }
}

/// **The token difference reaches a reader, rather than being written and forgotten.**
///
/// A comparison run records how many more tokens the model read and wrote per attempt with the skill than
/// without it. That figure was written into the saved file and read back by nothing, while the summary
/// line that would show it printed a dash whatever had happened — a number the record promised that no
/// reader could obtain.
@Suite("A comparison carries its token difference through to what is shown")
struct TokenDeltaSurfacedTests {
    private func trial(_ passed: Bool, tokens: TokenCounts?, exit: TrialExit = .passed) -> TrialResult {
        TrialResult(exit: exit,
                    verdicts: exit == .polluted ? [] : [Verdict(criterion: "c", passed: passed, rationale: "r",
                                                                judgeId: "j", model: "m", judgePromptVersion: "v")],
                    durationSeconds: 1, tokens: tokens)
    }

    private func counts(_ n: Int) throws -> TokenCounts {
        try #require(TokenCounts(uncachedInput: n, cacheRead: 0, cacheWrite: 0, output: 0))
    }

    private func comparison(withTokens: TokenCounts?, baseTokens: TokenCounts?) throws -> ABComparison {
        ABComparison(
            withArm: try UniqueByName([EvalResult(evalId: "a", trials: [trial(true, tokens: withTokens)])],
                                      name: \.evalId),
            baseline: try UniqueByName([EvalResult(evalId: "a", trials: [trial(false, tokens: baseTokens)])],
                                       name: \.evalId))
    }

    @Test("A run that counted both sides carries the difference")
    func bothSidesCarryTheDifference() throws {
        #expect(try comparison(withTokens: try counts(900), baseTokens: try counts(400)).tokenDeltaPerAttempt == 500)
    }

    /// A difference needs two measurements — the same rule the wall-clock figure beside it follows.
    @Test("One side counting nothing means there is no difference to carry", arguments: [true, false])
    func oneSidedCarriesNothing(withSideCounted: Bool) throws {
        let ab = try comparison(withTokens: withSideCounted ? try counts(900) : nil,
                                baseTokens: withSideCounted ? nil : try counts(400))
        #expect(ab.tokenDeltaPerAttempt == nil)
    }

    /// **A live run and the same run re-derived from its own file must not disagree.** The difference is
    /// an average, and averages are fractional whenever the two sides recorded different numbers of
    /// attempts — which is any run where one attempt was thrown out. Rounded to whole tokens, a run
    /// reporting `90.5` saved `+90` and read back as `90`.
    @Test("A fractional average survives being written and read back")
    func fractionalAverageSurvives() throws {
        func attempt(_ passed: Bool, _ n: Int) -> TrialResult {
            TrialResult(exit: .passed,
                        verdicts: [Verdict(criterion: "c", passed: passed, rationale: "r",
                                           judgeId: "j", model: "m", judgePromptVersion: "v")],
                        durationSeconds: 1,
                        tokens: TokenCounts(uncachedInput: n, cacheRead: 0, cacheWrite: 0, output: 0))
        }
        // Three attempts on one side, two on the other, so both averages are fractional.
        let withArm = [EvalResult(evalId: "a", trials: [attempt(true, 100), attempt(true, 101), attempt(true, 102)])]
        let baseline = [EvalResult(evalId: "a", trials: [attempt(false, 10), attempt(false, 11)])]
        let live = try RunReport(skill: "demo", results: withArm, baseline: baseline)
        #expect(live.ab?.tokenDeltaPerAttempt == 90.5, "101 on average against 10.5")

        let record = try BenchmarkFile(
            skill: "demo", behavioral: (report: live, evals: withArm), baseline: baseline,
            trigger: nil, harness: "replay", k: 3,
            provenance: RunProvenance(judgeProvider: "p", judgeModel: "m",
                                      judgePromptVersion: "v", executorBinaryVersion: "x"),
            preserving: nil)
        #expect(record.runSummary?["delta"]?.objectValue?["total_tokens_per_attempt"] == .string("+90.50"))
        #expect(try RunReport(benchmark: record).ab?.tokenDeltaPerAttempt == 90.5,
                "the figure re-derived from the file must match the one the run reported")
    }

    /// **It survives being written to a file and read back**, which is the round trip that was missing:
    /// the figure was written and the reading side had no way to ask for it.
    @Test("The difference survives a round trip through the saved file")
    func survivesTheRoundTrip() throws {
        let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                       judgePromptVersion: "v", executorBinaryVersion: "x")
        let withArm = [EvalResult(evalId: "a", trials: [trial(true, tokens: try counts(900))])]
        let baseline = [EvalResult(evalId: "a", trials: [trial(false, tokens: try counts(400))])]
        let record = try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, baseline: baseline), evals: withArm),
            baseline: baseline, trigger: nil, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
        #expect(record.runSummary?["delta"]?.objectValue?["total_tokens_per_attempt"] == .string("+500.00"))
        #expect(try RunReport(benchmark: record).ab?.tokenDeltaPerAttempt == 500,
                "read back, not just written")
    }
}

/// **A figure written into the results file must mean the same thing on every machine.**
///
/// Differences between two runs are written into the file as short pieces of text like `+0.50`, and read
/// back with a plain text-to-number conversion that only understands a dot. If those figures were written
/// using the machine's regional conventions, two things break: on a comma-decimal machine `+0,50` reads
/// back as nothing at all, and a four-figure count written with a grouping mark as `+1,100` reads back as
/// `1` — the same measurement off by three orders of magnitude, with nothing to show for it.
///
/// **The values matter more than the assertions here.** Every existing test of this block uses figures
/// under a thousand, which look identical whether regional conventions are applied or not — so they pass
/// on any machine and would keep passing if this broke. The four-figure difference below is what makes a
/// regression visible without needing to run the suite on a differently-configured machine: applying
/// regional conventions inserts a grouping mark even in English.
@Suite("Figures in the results file are written the same way on every machine")
struct NeutralNumberFormatTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")

    private func trial(_ passed: Bool, tokens: TokenCounts?) -> TrialResult {
        TrialResult(exit: .passed,
                    verdicts: [Verdict(criterion: "c", passed: passed, rationale: "r",
                                       judgeId: "j", model: "m", judgePromptVersion: "v")],
                    durationSeconds: 1, tokens: tokens)
    }

    private func counts(_ n: Int) throws -> TokenCounts {
        try #require(TokenCounts(uncachedInput: n, cacheRead: 0, cacheWrite: 0, output: 0))
    }

    /// 1500 with the skill against 400 without it — a difference of 1100, which is above the point where
    /// regional conventions start inserting a grouping mark.
    private func record() throws -> BenchmarkFile {
        let withArm = [EvalResult(evalId: "a", trials: [trial(true, tokens: try counts(1500))])]
        let baseline = [EvalResult(evalId: "a", trials: [trial(false, tokens: try counts(400))])]
        return try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, baseline: baseline), evals: withArm),
            baseline: baseline, trigger: nil, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
    }

    @Test("A four-figure difference is written plainly, with no grouping mark")
    func fourFigureDifferenceHasNoGroupingMark() throws {
        let written = try #require(record().runSummary?["delta"]?
            .objectValue?["total_tokens_per_attempt"]?.stringValue)
        #expect(written == "+1100.00", "got \(written) — a grouping mark means regional conventions crept in")
        #expect(!written.contains(","), "a comma here cannot be read back at all")
    }

    /// The consequence, not just the spelling: the figure survives being written and read again.
    @Test("A four-figure difference survives being written and read back")
    func fourFigureDifferenceRoundTrips() throws {
        #expect(try RunReport(benchmark: try record()).ab?.tokenDeltaPerAttempt == 1100,
                "a grouping mark would read back as 1, not 1100")
    }

    /// The decimal mark, on the field where values stay small — this one cannot be caught by a grouping
    /// mark, so it is asserted directly.
    @Test("A fractional difference uses a dot, which is what reads back")
    func fractionalDifferenceUsesADot() throws {
        let written = try #require(record().runSummary?["delta"]?.objectValue?["pass_rate"]?.stringValue)
        #expect(written.contains("."), "got \(written) — a comma decimal mark reads back as nothing")
        #expect(!written.contains(","))
        #expect(Double(written) != nil, "and the conversion used on the way back in must accept it")
    }
}

/// **A run's summary and the results it was built from must describe the same tests.** They are matched
/// up position by position when the file is written, and pairing two lists that way silently stops at the
/// shorter one: measured, a summary describing three tests handed one result recorded a single row, and
/// the other two vanished from the committed file. That is the same fault as quietly scoring fewer tests
/// than a file lists, which this file already refuses in two other places.
@Suite("A run's summary and its results must describe the same tests")
struct SummaryResultsAgreementTests {
    private func result(_ id: String) -> EvalResult {
        EvalResult(evalId: id, trials: [TrialResult(
            exit: .passed,
            verdicts: [Verdict(criterion: "c", passed: true, rationale: "r",
                               judgeId: "j", model: "m", judgePromptVersion: "v")],
            durationSeconds: 1)])
    }

    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")

    private func record(summarising: [String], from: [String]) throws -> BenchmarkFile {
        try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: summarising.map(result)),
                         evals: from.map(result)),
            baseline: nil, trigger: nil, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
    }

    @Test("Fewer results than the summary describes is refused, not silently trimmed")
    func fewerResultsRefused() {
        #expect(throws: EDDError.self) { _ = try record(summarising: ["a", "b", "c"], from: ["a"]) }
    }

    @Test("The same tests in a different order is refused too")
    func differentOrderRefused() {
        #expect(throws: EDDError.self) { _ = try record(summarising: ["a", "b"], from: ["b", "a"]) }
    }

    @Test("Matching lists are recorded in full")
    func matchingListsRecorded() throws {
        let rows = try record(summarising: ["a", "b", "c"], from: ["a", "b", "c"])
            .fields["consistency"]?.objectValue?["per_eval"]?.arrayValue ?? []
        #expect(rows.count == 3, "every test the summary describes reaches the file")
    }
}

/// **An attempt that was never graded must not drag the saved score down.**
///
/// The score stopped counting ungraded attempts, but three separate places assembled the list of
/// per-attempt scores that goes into the saved file, each filtering attempts slightly differently, and an
/// ungraded attempt slipped into all three as a zero. So a check with two passing attempts and one that
/// never produced a result was written to the file as scoring two-thirds, while the same run's headline
/// said it passed outright. The file is read by other tooling, so a wrong number there outlives the run.
@Suite("The saved file scores only the attempts that were graded")
struct SavedScoreCountsGradedOnlyTests {
    private func verdict(_ passed: Bool) -> Verdict {
        Verdict(criterion: "c", passed: passed, rationale: "r", judgeId: "t", model: "m", judgePromptVersion: "1")
    }
    private func attempt(_ exit: TrialExit, passed: Bool) -> TrialResult {
        TrialResult(exit: exit, verdicts: exit == .error ? [] : [verdict(passed)],
                    durationSeconds: 1, tokens: TokenCounts(uncachedInput: 5, output: 5))
    }
    private func saved(_ trials: [TrialResult]) throws -> BenchmarkFile {
        let withArm = [EvalResult(evalId: "a", trials: trials)]
        return try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm), evals: withArm),
            baseline: nil, trigger: nil, harness: "replay", k: trials.count,
            provenance: RunProvenance(judgeProvider: "p", judgeModel: "m",
                                      judgePromptVersion: "v", executorBinaryVersion: "x"),
            preserving: nil)
    }
    private func row(_ file: BenchmarkFile) throws -> [String: JSONValue] {
        let rows = file.fields["consistency"]?.objectValue?["per_eval"]?.arrayValue ?? []
        return try #require(rows.first?.objectValue)
    }

    @Test("Two graded attempts that passed and one never graded is recorded as a full score")
    func ungradedAttemptDoesNotLowerTheSavedScore() throws {
        let entry = try row(try saved([attempt(.passed, passed: true),
                                       attempt(.passed, passed: true),
                                       attempt(.error, passed: false)]))
        #expect(entry["mean_pass_rate"] == .number(1),
                "every graded attempt passed; two-thirds would contradict the run's headline figure")
        #expect(entry["pass_power_k"] == .number(1), "and it counts as having passed throughout")
    }

    /// The other half, so this cannot be satisfied by never recording a low score.
    @Test("A graded attempt that failed still lowers the saved score")
    func gradedFailureStillCounts() throws {
        let entry = try row(try saved([attempt(.passed, passed: true), attempt(.failed, passed: false)]))
        #expect(entry["mean_pass_rate"] == .number(0.5), "one of two graded attempts passed")
        #expect(entry["pass_power_k"] == .number(0), "so it did not pass throughout")
    }
}

/// **A saved run must state the same numbers as the run that produced it.**
///
/// The without-skill side counted attempts that were merely not disqualified, while scoring only the ones
/// actually graded — two different sets of attempts feeding the same row. Two failures came out of that.
///
/// When every attempt on that side failed to grade, the count was above zero with no scores to average, so
/// the row divided by nothing. Writing the results file then failed outright with "cannot write
/// not-a-number" — **after** the run had finished and the money had been spent.
///
/// Short of that, the two sets simply disagreed: the saved file stated a different denominator from the
/// live run, so re-checking the file against the run it came from gave a different answer. That is the one
/// promise this file exists to keep.
@Suite("A saved run states the same numbers as the run that produced it")
struct SavedRunMatchesLiveRunTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")
    private func verdict(_ passed: Bool) -> Verdict {
        Verdict(criterion: "c", passed: passed, rationale: "r", judgeId: "t", model: "m", judgePromptVersion: "1")
    }
    private func attempt(_ exit: TrialExit, passed: Bool = false) -> TrialResult {
        TrialResult(exit: exit, verdicts: exit == .error ? [] : [verdict(passed)], durationSeconds: 1, tokens: nil)
    }
    private func saved(withSkill: [TrialResult], without: [TrialResult]) throws -> BenchmarkFile {
        let withArm = [EvalResult(evalId: "e", trials: withSkill)]
        let baseline = [EvalResult(evalId: "e", trials: without)]
        return try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, baseline: baseline), evals: withArm),
            baseline: baseline, trigger: nil, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
    }

    /// The run had already finished and been paid for when this threw.
    @Test("A without-skill side where nothing could be graded still writes")
    func nothingGradableStillWrites() throws {
        let file = try saved(withSkill: [attempt(.passed, passed: true)],
                             without: [attempt(.error), attempt(.error)])
        #expect(throws: Never.self) { try JSONEncoder().encode(file) }

        let rows = file.fields["consistency"]?.objectValue?["per_eval"]?.arrayValue ?? []
        let row = try #require(rows.first { $0.objectValue?["arm"]?.stringValue == "baseline" }?.objectValue)
        #expect(row["runs"] == .number(0), "nothing was graded, so nothing counts")
        #expect(row["mean_pass_rate"] == nil, "and there is no score to state")
    }

    /// The quieter half: no crash, just two numbers that disagree.
    @Test("Reading the saved run back gives the same comparison the run reported")
    func savedRunReReadsTheSame() throws {
        let file = try saved(withSkill: [attempt(.passed, passed: true)],
                             without: [attempt(.passed, passed: true), attempt(.error)])
        let live = try #require(try RunReport(skill: "demo",
                                              results: [EvalResult(evalId: "e", trials: [attempt(.passed, passed: true)])],
                                              baseline: [EvalResult(evalId: "e", trials: [attempt(.passed, passed: true),
                                                                                          attempt(.error)])]).ab)
        let reread = try #require(try RunReport(benchmark: file).ab)
        #expect(reread.perEval[0].baselineRecorded == live.perEval[0].baselineRecorded,
                "the saved file must not claim a different number of attempts than the run did")
        #expect(reread.pairedMeanDelta == live.pairedMeanDelta,
                "and must not therefore report a different difference")
    }
}

/// **The whole-run summaries score only what was graded, on every side.**
///
/// Three separate places averaged the per-attempt scores. Two were corrected and the without-skill side
/// and the routing side were not, so on those an attempt that never produced a result was averaged in as
/// an attempt that scored nothing. The summary then sat below the per-check rows in the same file saying a
/// lower number, and where every routing attempt failed to grade it stated a flat "nothing passed" for a
/// check that was never measured — which its own comment says it must never do.
@Suite("Whole-run summaries score only graded attempts")
struct SummaryScoresGradedOnlyTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")
    private func verdict(_ passed: Bool) -> Verdict {
        Verdict(criterion: "c", passed: passed, rationale: "r", judgeId: "t", model: "m", judgePromptVersion: "1")
    }
    private func attempt(_ exit: TrialExit, passed: Bool = false) -> TrialResult {
        TrialResult(exit: exit, verdicts: exit == .error ? [] : [verdict(passed)], durationSeconds: 1, tokens: nil)
    }

    @Test("The without-skill summary ignores attempts that never produced a result")
    func withoutSkillSummaryIgnoresUngraded() throws {
        let withArm = [EvalResult(evalId: "e", trials: [attempt(.passed, passed: true)])]
        let baseline = [EvalResult(evalId: "e", trials: [attempt(.passed, passed: true), attempt(.error)])]
        let file = try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, baseline: baseline), evals: withArm),
            baseline: baseline, trigger: nil, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
        let arm = try #require(file.runSummary?["without_skill"]?.objectValue)
        let rate = try #require(arm["pass_rate"]?.objectValue?["mean"]?.numberValue)
        #expect(rate == 1.0, "the one graded attempt passed; averaging the ungraded one in would say half")
    }

    @Test("A routing check where nothing could be graded states no rate at all")
    func routingSummaryStatesNothingWhenNothingGraded() throws {
        let withArm = [EvalResult(evalId: "e", trials: [attempt(.passed, passed: true)])]
        let routing = [TriggerEvalResult(evalId: "t", query: "q", shouldTrigger: true,
                                         trials: [TriggerTrialResult(exit: .error, firedTarget: false)])]
        let file = try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, trigger: routing), evals: withArm),
            baseline: nil, trigger: routing, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
        let summary = file.runSummary?["trigger"]?.objectValue
        #expect(summary?["pass_rate"] == nil,
                "nothing was graded, so a flat zero would read as 'the skill never fired', unmeasured")
    }
}

/// **An arm that measured nothing states nothing — including the container.**
///
/// Each figure inside a run's per-arm block is withheld rather than invented when there is nothing behind
/// it: no score, no timing, no cost. But the block *holding* none of them was still written, so a run
/// where every attempt failed to be set up produced an arm whose entire value was an empty object. The
/// three rules inside were right and the container ignored them.
///
/// Reachable in practice: an attempt whose workspace cannot be prepared records no verdicts, no duration
/// and no cost, so a run where that happens to every attempt has nothing to put in the block at all.
@Suite("An arm with nothing measured is left out entirely")
struct EmptyArmIsOmittedTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")
    private func saved(_ trials: [TrialResult]) throws -> BenchmarkFile {
        let arm = [EvalResult(evalId: "a", trials: trials)]
        return try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: arm), evals: arm),
            baseline: nil, trigger: nil, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
    }

    @Test("Every attempt failing to start leaves no arm behind, not an empty one")
    func nothingMeasuredWritesNoArm() throws {
        let file = try saved([TrialResult(exit: .error, verdicts: [])])
        #expect(file.runSummary?["default"] == nil,
                "there is nothing to say about this arm, so it should not appear at all")
    }

    /// The other half, so this cannot be satisfied by never writing an arm.
    @Test("An arm with something to report still appears")
    func measuredArmStillAppears() throws {
        let verdict = Verdict(criterion: "c", passed: true, rationale: "r",
                              judgeId: "t", model: "m", judgePromptVersion: "1")
        let file = try saved([TrialResult(exit: .passed, verdicts: [verdict], durationSeconds: 1, tokens: nil)])
        let arm = try #require(file.runSummary?["default"]?.objectValue)
        #expect(!arm.isEmpty, "this arm measured something and must say so")
        #expect(arm["pass_rate"] != nil)
    }
}

/// **The per-attempt rows and the figures they add up to must agree about what was graded.**
///
/// A routing attempt that never ran was written as a row saying one thing was checked and it failed —
/// while the evidence text in the very same row read "not measured". The object contradicted itself. And
/// the summary beside it already left such attempts out, so anything recomputing a rate from the rows got
/// a different answer from the recompute this file exists to support.
///
/// The line drawn is exactly the summary's: attempts that never ran are left out; an attempt that ran out
/// of time is kept, because it did answer the question — the skill did not fire in the time allowed — and
/// the summary counts it.
@Suite("Routing rows and the summary agree about what was graded")
struct RoutingRowsMatchSummaryTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")
    private func row(forRoutingExit exit: TrialExit) throws -> [String: JSONValue] {
        let routing = [TriggerEvalResult(evalId: "t", query: "q", shouldTrigger: true,
                                         trials: [TriggerTrialResult(exit: exit, firedTarget: false)])]
        let withArm = [EvalResult(evalId: "a", trials: [TrialResult(exit: .passed, verdicts: [
            Verdict(criterion: "c", passed: true, rationale: "r", judgeId: "t", model: "m", judgePromptVersion: "1")])])]
        let file = try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, trigger: routing), evals: withArm),
            baseline: nil, trigger: routing, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
        let rows = file.fields["runs"]?.arrayValue ?? []
        return try #require(rows.first { $0.objectValue?["configuration"]?.stringValue == "trigger" }?.objectValue)
    }

    @Test("An attempt that never ran is recorded as nothing checked, not as a failure")
    func neverRanIsNotAFailure() throws {
        let entry = try row(forRoutingExit: .error)
        #expect(entry["result"]?.objectValue?["total"] == .number(0), "nothing was checked")
        #expect(entry["result"]?.objectValue?["failed"] == .number(0), "so nothing failed")
        #expect(entry["expectations"]?.arrayValue?.isEmpty == true,
                "and no check is listed, which is what the evidence text already said")
    }

    /// The other half: running out of time answered the question, and the summary counts it, so the row
    /// must too — otherwise the two disagree in the opposite direction.
    @Test("An attempt that ran out of time is still a graded failure")
    func timedOutIsStillGraded() throws {
        let entry = try row(forRoutingExit: .timeout)
        #expect(entry["result"]?.objectValue?["total"] == .number(1), "the skill did not fire in time")
        #expect(entry["result"]?.objectValue?["failed"] == .number(1))
        // **The words must agree with the figures beside them.** Fixing the figures left the wording
        // saying "not measured" on a row that now records a measured failure — the contradiction moved
        // from the numbers into the text rather than going away.
        let evidence = entry["expectations"]?.arrayValue?.first?.objectValue?["evidence"]?.stringValue
        #expect(evidence?.contains("not measured") != true, "this row records a graded failure: \(evidence ?? "none")")
        #expect(evidence?.contains("ran out of time") == true)
    }

    @Test("An attempt that fired as expected is recorded as passing")
    func passingIsRecorded() throws {
        let routing = [TriggerEvalResult(evalId: "t", query: "q", shouldTrigger: true,
                                         trials: [TriggerTrialResult(exit: .passed, firedTarget: true)])]
        let withArm = [EvalResult(evalId: "a", trials: [TrialResult(exit: .passed, verdicts: [
            Verdict(criterion: "c", passed: true, rationale: "r", judgeId: "t", model: "m", judgePromptVersion: "1")])])]
        let file = try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: withArm, trigger: routing), evals: withArm),
            baseline: nil, trigger: routing, harness: "replay", k: 1,
            provenance: provenance, preserving: nil)
        let entry = try #require((file.fields["runs"]?.arrayValue ?? [])
            .first { $0.objectValue?["configuration"]?.stringValue == "trigger" }?.objectValue)
        #expect(entry["result"]?.objectValue?["passed"] == .number(1))
        #expect(entry["result"]?.objectValue?["total"] == .number(1))
    }
}
