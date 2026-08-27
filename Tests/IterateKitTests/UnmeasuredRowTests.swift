import Testing
import Foundation
import EDDCore
@testable import IterateKit

/// **A test that nothing ran is not a test that scored the same.**
///
/// Proving an edit means running the same tests before and after it and comparing. A test can end up
/// with no runs recorded at all — one with no instruction to send cannot be run, and a test that exists
/// before an edit can be gone after it. In the counts those look identical to a test that ran and scored
/// zero, and they used to be treated identically: the non-measurement went into the average change as a
/// difference of exactly zero, dragging the headline toward nothing and inventing spread around it.
///
/// The two rules being reconciled here are both real and pull opposite ways. Benchmark reporting says a
/// task that crashed must count as zero rather than be dropped, or scores inflate by discarding
/// inconvenient results — that governs the *verdict*, and it is unchanged below. Metrics reporting says
/// "no data" and "zero" mean different things and must not be shown as one — that governs the *average*,
/// which is what changes.
@Suite("A test with no runs is out of the average and still in the verdict")
struct UnmeasuredRowTests {
    private func measurement(_ id: String, _ passes: Int, of recorded: Int) -> EditVerdict.Measurement {
        EditVerdict.Measurement(id: id, passes: passes, recorded: recorded)
    }

    private func compare(before: [EditVerdict.Measurement],
                         after: [EditVerdict.Measurement]) throws -> EditVerdict.Outcome {
        EditVerdict.compare(before: try UniqueByName(before, name: \.id),
                            after: try UniqueByName(after, name: \.id))
    }

    /// The exact shape that was printing `+0.50 ± 0.50`: one test that genuinely improved by a whole
    /// unit, beside one that never ran. The improvement is the only measurement, so it is the average.
    @Test("A test with no runs does not drag the average toward zero")
    func unmeasuredDoesNotDilute() throws {
        let outcome = try compare(
            before: [measurement("real", 0, of: 3), measurement("never-ran", 0, of: 0)],
            after: [measurement("real", 3, of: 3), measurement("never-ran", 0, of: 0)])
        #expect(outcome.meanDelta == 1.0, "the one thing that was measured moved by a whole unit")
        #expect(outcome.standardError == nil,
                "one measurement says nothing about spread — a second, unmeasured row must not invent it")
        #expect(outcome.unmeasured.map(\.id) == ["never-ran"], "and the test nothing ran is named")
    }

    /// **The safety rule this must not weaken.** A test that ran before the edit and is gone after it was
    /// measured — that is a real and bad difference. It keeps its place in the average *and* blocks, or
    /// deleting a passing test would read as "nothing got worse".
    @Test("A test that disappears after the edit still counts and still blocks")
    func disappearingTestStillBlocks() throws {
        let outcome = try compare(before: [measurement("gone", 3, of: 3)], after: [])
        #expect(outcome.unmeasured.isEmpty, "one side ran, so this was measured")
        #expect(outcome.meanDelta == -1.0)
        #expect(!outcome.proven, "an edit that removes a passing test is refused")
    }

    /// The mirror: a test that appears only after the edit was also measured, and counts.
    @Test("A test that only exists after the edit counts as measured")
    func appearingTestCounts() throws {
        let outcome = try compare(before: [], after: [measurement("new", 3, of: 3)])
        #expect(outcome.unmeasured.isEmpty)
        #expect(outcome.meanDelta == 1.0)
    }

    /// Running and failing every repeat is a measurement of zero, which is not the same as no runs. It
    /// stays in the average, where it belongs.
    @Test("A test that ran and failed every repeat is measured, and counts")
    func failingEveryRepeatIsMeasured() throws {
        let outcome = try compare(
            before: [measurement("fails", 0, of: 3), measurement("real", 0, of: 2)],
            after: [measurement("fails", 0, of: 3), measurement("real", 2, of: 2)])
        #expect(outcome.unmeasured.isEmpty, "three runs that all failed are still three runs")
        #expect(outcome.meanDelta == 0.5, "averaged over both, not over the improving one alone")
    }

    @Test("When nothing ran anywhere there is no average to state")
    func nothingRanAnywhere() throws {
        let outcome = try compare(before: [measurement("a", 0, of: 0)], after: [measurement("a", 0, of: 0)])
        #expect(outcome.unmeasured.map(\.id) == ["a"])
        #expect(outcome.standardError == nil)
        #expect(outcome.proven, "nothing scored lower, because nothing scored at all")
    }

    /// **Leaving a test out of the average is still an omission, so it is stated.** The route to this
    /// from the command is closed — a test with no instruction to send is refused before anything is
    /// spent — which is precisely why the wording is built here and checked here rather than left as
    /// prose at the place it is printed.
    @Test("Tests left out of the average are named, with what happened to them")
    func omissionIsStated() throws {
        let outcome = try compare(before: [measurement("real", 0, of: 2), measurement("never-ran", 0, of: 0)],
                                  after: [measurement("real", 2, of: 2), measurement("never-ran", 0, of: 0)])
        let disclosure = try #require(outcome.unmeasuredDisclosure)
        #expect(disclosure.reason.contains("never-ran"), "it says which test")
        #expect(disclosure.reason.contains("average"), "and what it was left out of")
        #expect(!disclosure.reason.contains("real"), "and does not accuse the test that did run")
    }

    @Test("More than one such test reads as more than one")
    func omissionPluralises() throws {
        let outcome = try compare(before: [measurement("a", 0, of: 0), measurement("b", 0, of: 0)],
                                  after: [measurement("a", 0, of: 0), measurement("b", 0, of: 0)])
        let disclosure = try #require(outcome.unmeasuredDisclosure)
        #expect(disclosure.reason.contains("a, b"))
        #expect(disclosure.reason.contains("they are"))
    }

    @Test("An ordinary run states no such omission")
    func ordinaryRunStatesNothing() throws {
        let outcome = try compare(before: [measurement("a", 0, of: 2)], after: [measurement("a", 2, of: 2)])
        #expect(outcome.unmeasuredDisclosure == nil, "nothing was left out, so nothing is claimed to be")
    }
}

/// The machine-readable side of the same distinction: a script reading the payload must be able to tell
/// a test that recorded nothing from one that ran and scored zero, without inferring it from the counts.
@Suite("The payload marks which tests were measured")
struct UnmeasuredPayloadTests {
    private func row(recorded: Int) -> IterateReport.Comparison.Row {
        .init(id: "e", beforePasses: 0, beforeRecorded: recorded,
              afterPasses: 0, afterRecorded: recorded, delta: 0, noisy: false)
    }

    /// **Derived, not supplied.** The counts already say whether anything ran, so there is no argument to
    /// pass and therefore no way for the flag and the counts to disagree.
    @Test("Whether a test was measured is read off its counts, not handed in")
    func derivedFromCounts() {
        #expect(row(recorded: 0).measured == false)
        #expect(row(recorded: 1).measured == true)
    }

    @Test("A test measured on one side only still counts as measured")
    func oneSidedIsMeasured() {
        let vanished = IterateReport.Comparison.Row(
            id: "gone", beforePasses: 3, beforeRecorded: 3,
            afterPasses: 0, afterRecorded: 0, delta: -1, noisy: false)
        #expect(vanished.measured, "it ran before the edit — that is a measurement, and a bad difference")
    }

    @Test("The payload names the tests nothing ran, and says whether anything did")
    func namesTheUnmeasured() {
        let comparison = IterateReport.Comparison(
            perEval: [row(recorded: 0),
                      .init(id: "ran", beforePasses: 1, beforeRecorded: 1,
                            afterPasses: 1, afterRecorded: 1, delta: 0, noisy: false)],
            meanDelta: 0, standardError: nil, improved: 0, regressed: 0)
        #expect(comparison.unmeasuredIds == ["e"])
        #expect(comparison.anythingMeasured)

        let none = IterateReport.Comparison(perEval: [row(recorded: 0)], meanDelta: 0,
                                            standardError: nil, improved: 0, regressed: 0)
        #expect(!none.anythingMeasured, "nothing ran anywhere, so there is no average to trust")
    }
}

/// **When a verdict rests on nothing having passed, it says so.**
///
/// The rule for approving an edit is "no test scored lower". That is satisfied trivially when every test
/// fails on both sides — nothing can score lower than nothing — so the edit is approved and the line
/// offering to apply it prints directly underneath. Both statements are true and together they are
/// misleading advice. The verdict itself is left alone, since nothing did get worse; what changes is that
/// the reader is told what it rests on, immediately above the suggestion to act on it.
@Suite("A verdict resting on nothing passing says so")
struct NoPassingEvidenceTests {
    private func measurement(_ id: String, _ passes: Int, of recorded: Int) -> EditVerdict.Measurement {
        EditVerdict.Measurement(id: id, passes: passes, recorded: recorded)
    }

    private func compare(before: [EditVerdict.Measurement],
                         after: [EditVerdict.Measurement]) throws -> EditVerdict.Outcome {
        EditVerdict.compare(before: try UniqueByName(before, name: \.id),
                            after: try UniqueByName(after, name: \.id))
    }

    /// The shape a misnamed file of recorded answers produced, and which a skill failing everything
    /// produces without any of that.
    @Test("Everything failing on both sides is approved, and disclosed as resting on nothing")
    func nothingPassedIsDisclosed() throws {
        let outcome = try compare(before: [measurement("a", 0, of: 1), measurement("b", 0, of: 1)],
                                  after: [measurement("a", 0, of: 1), measurement("b", 0, of: 1)])
        #expect(outcome.proven, "nothing scored lower, which is still true and still the verdict")
        let disclosure = try #require(outcome.noPassingEvidenceDisclosure)
        #expect(disclosure.reason.contains("no evidence"), "and the reader is told what that rests on")
    }

    /// One passing check anywhere is evidence, so nothing is claimed.
    @Test("A single pass anywhere means nothing is claimed", arguments: [true, false])
    func onePassAnywhereIsEnough(passedBefore: Bool) throws {
        let outcome = try compare(before: [measurement("a", passedBefore ? 1 : 0, of: 1)],
                                  after: [measurement("a", passedBefore ? 0 : 1, of: 1)])
        #expect(outcome.noPassingEvidenceDisclosure == nil)
    }

    /// A run where nothing was measured at all is already covered by its own disclosure; claiming both
    /// would say the same thing twice in different words.
    @Test("A run that measured nothing does not also claim nothing passed")
    func unmeasuredRunClaimsOnlyOnce() throws {
        let outcome = try compare(before: [measurement("a", 0, of: 0)], after: [measurement("a", 0, of: 0)])
        #expect(outcome.unmeasuredDisclosure != nil, "this is the one that applies")
        #expect(outcome.noPassingEvidenceDisclosure == nil, "and not this one as well")
    }
}
