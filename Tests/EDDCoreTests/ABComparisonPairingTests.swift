import Testing
import EDDCore

/// When the switched-off measurement yields nothing, saying so must be distinguishable from saying the
/// comparison came out flat: the first has nothing in it to read, the second has a real answer of zero.
///
/// Tested here rather than through the built tool because the offline stand-ins cannot produce the state
/// — they never let a skill fire during a switched-off measurement — so an end-to-end test would be one
/// that cannot fail.
@Suite("ABComparison — telling 'no comparison' from 'no difference'")
struct ABComparisonPairingTests {
    /// `baseRecorded: 0` is a switched-off measurement that produced nothing for that test.
    private func comparison(_ pairs: [ABComparison.Pair], polluted: Int = 0) -> ABComparison {
        ABComparison(pairs: pairs, timeDeltaSeconds: nil, polluted: polluted)
    }

    @Test("Every pairing unmeasured ⇒ no comparison was drawn")
    func allUnmeasured() {
        let ab = comparison([(id: "a", withPasses: 3, withRecorded: 3, basePasses: 0, baseRecorded: 0),
                             (id: "b", withPasses: 3, withRecorded: 3, basePasses: 0, baseRecorded: 0)],
                            polluted: 6)
        #expect(ab.producedNoPairing)
        #expect(ab.unmeasuredEvalIds.count == 2)
    }

    @Test("One pairing measured ⇒ there is a comparison, however small")
    func someMeasured() {
        #expect(!comparison([(id: "a", withPasses: 3, withRecorded: 3, basePasses: 0, baseRecorded: 0),
                             (id: "b", withPasses: 3, withRecorded: 3, basePasses: 1, baseRecorded: 3)])
            .producedNoPairing)
    }

    @Test("A difference of zero is a result, and must not read as an absent comparison")
    func flatIsNotAbsent() {
        let ab = comparison([(id: "a", withPasses: 3, withRecorded: 3, basePasses: 3, baseRecorded: 3),
                             (id: "b", withPasses: 3, withRecorded: 3, basePasses: 3, baseRecorded: 3)])
        #expect(!ab.producedNoPairing)
        #expect(ab.pairedMeanDelta == 0, "flat, and measured")
    }

    @Test("Nothing to compare is not the same as failing to compare")
    func emptyIsNotUnusable() {
        #expect(!comparison([]).producedNoPairing)
    }
}

/// The proving command's report says its repeat count is "as observed rather than as requested". It used
/// to be handed in, so the requested number was passed instead and a report claimed three repeats beside
/// a row that had recorded none — disagreeing with the measuring command about the same skill.
///
/// Tested here rather than through the built tool: the only way to record fewer repeats than were asked
/// for was a test with no instruction to send, and that is now refused before anything runs — so the
/// end-to-end version of this test could no longer reach the state it was written for.
@Suite("IterateReport — the repeats reported are the ones that happened")
struct IterateObservedRepeatsTests {
    private func report(_ rows: [(before: Int, after: Int)]) -> IterateReport {
        IterateReport(
            skill: "demo", proposals: "fix.json", edits: [0], proven: true,
            comparison: .init(
                perEval: rows.enumerated().map { index, row in
                    .init(id: "e\(index)", beforePasses: 0, beforeRecorded: row.before,
                          afterPasses: 0, afterRecorded: row.after, delta: 0, noisy: false)
                },
                meanDelta: 0, standardError: nil, improved: 0, regressed: 0))
    }

    /// **A test that ran on neither side no longer drags this to zero, and that expectation flipped for a
    /// reason.** This figure sits in the same printed line as the average change, and the average leaves
    /// such tests out — so counting them here made one line contradict itself: a real average of `+1.00`
    /// from a test that ran three times each side, beside a claim that the fewest repeats any test
    /// recorded was none. It now counts the same tests the average is drawn from. Nothing is hidden by
    /// that: those tests are named in the run's omissions list.
    @Test("A test that ran on neither side is not counted in the reported repeats")
    func unrecordedTestIsNotCounted() {
        #expect(report([(3, 3), (0, 0)]).observedK == 3,
                "the test that ran recorded three; the one that never ran describes no repeats")
    }

    /// When nothing ran anywhere there is nothing to count, and the printed line says as much instead of
    /// stating an average — so zero here still means what it always did.
    @Test("With nothing measured anywhere it is still zero")
    func nothingMeasuredIsStillZero() {
        #expect(report([(0, 0), (0, 0)]).observedK == 0)
    }

    @Test("Otherwise it is the fewest any test recorded, across both measurements")
    func fewestAcrossBothMeasurements() {
        #expect(report([(3, 3), (3, 2)]).observedK == 2)
        #expect(report([(3, 3), (3, 3)]).observedK == 3)
    }

    @Test("No tests at all reports zero rather than guessing")
    func emptyIsZero() {
        #expect(report([]).observedK == 0)
    }
}
