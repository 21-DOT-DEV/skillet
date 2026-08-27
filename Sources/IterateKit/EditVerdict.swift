import Foundation
import EDDCore

/// Comparing the same tests before and after an edit, and deciding whether the edit is safe to land.
///
/// **Pure.** It takes two sets of counts and returns a verdict; it reads no files and runs nothing, so
/// every case below is checkable without spending anything.
///
/// **Strict on purpose.** Any test scoring lower blocks, with no allowance made for the drop being
/// small. The two mistakes are not equally costly: wrongly blocking a good edit costs a re-run, while
/// wrongly calling a bad edit proven puts a regression into a file you then commit — at the exact moment
/// you have decided to trust this. The predecessor made the same call for the same reason: an edit that
/// fixes its target but breaks a sibling is blocked.
///
/// **Noise is shown, not excluded.** A grader disagrees with itself often enough that one test moving
/// from three-out-of-three to two-out-of-three is frequently run-to-run variation rather than damage. So
/// each row carries whether it sits inside that variation — and still blocks. Silently discounting a
/// drop would mean deciding, on an unmeasured error rate, which regressions are real.
public enum EditVerdict {
    /// One test's counts from one measurement: how many of its repeats passed, out of how many ran.
    public struct Measurement: Equatable, Sendable {
        public let id: String
        public let passes: Int
        public let recorded: Int

        public init(id: String, passes: Int, recorded: Int) {
            self.id = id; self.passes = passes; self.recorded = recorded
        }

        /// **Built from the record, so the count cannot be the total attempted by mistake.**
        ///
        /// This conversion used to sit in the command itself, where no test could reach it, and it used
        /// every attempt as the denominator. So an attempt that was never graded — a rate limit, a dropped
        /// connection — counted as a failed one, and a check that went from passing outright to "two of
        /// three graded, both passed" read as a **regression**, blocking an edit that was fine. That is a
        /// wrong decision about someone's work, taken from a network hiccup.
        public init(_ result: EvalResult) {
            self.init(id: result.evalId, passes: result.passes, recorded: result.measured)
        }

        /// The share of repeats that passed — `0` when nothing ran, which is what a test present in only
        /// one of the two measurements is compared against.
        var rate: Double { recorded > 0 ? Double(passes) / Double(recorded) : 0 }
        var status: EvalStatus { PassK.status(passes: passes, recorded: recorded) }
    }

    /// One test, before and after.
    public struct Row: Equatable, Sendable {
        public let id: String
        public let before: Measurement?
        public let after: Measurement?
        /// After minus before, as a share of repeats. Negative means it got worse.
        public let delta: Double
        /// This test does not settle to the same answer every time — in either measurement it passed
        /// some repeats and failed others. Its difference is therefore partly variation, which a reader
        /// needs told; it does **not** change whether a drop blocks.
        public let noisy: Bool

        public var regressed: Bool { delta < 0 }
        public var improved: Bool { delta > 0 }

        /// **Whether anything was actually run for this test, on either side.** A test that recorded no
        /// repeats in *either* measurement was not measured; a test that recorded repeats and failed them
        /// all was. The two look identical in the counts — both read `0/0` against `0/…` — and used to be
        /// treated identically, which put a non-measurement into the average change as though it were a
        /// change of zero.
        ///
        /// **One side is enough.** A test that ran before the edit and is gone after it *was* measured:
        /// that is a real, and bad, difference, and it must keep its place in the average and keep
        /// blocking. Only a test that ran on neither side has nothing to contribute.
        public var measured: Bool { (before?.recorded ?? 0) > 0 || (after?.recorded ?? 0) > 0 }
    }

    public struct Outcome: Equatable, Sendable {
        public let rows: [Row]
        /// Tests that ran on neither side, named. They keep their place in the table — a reader needs to
        /// see that they exist — but they are out of the average, and out of sight is not the same as out
        /// of mind, so they are named for the caller to disclose.
        public var unmeasured: [Row] { rows.filter { !$0.measured } }

        /// **Nothing passed anywhere, stated plainly, or nothing when something did.**
        ///
        /// The gate is "no test scored lower", which is satisfied trivially when every test fails on both
        /// sides: nothing can score lower than nothing. So an edit gets called proven off a run where not
        /// one check passed, and the line offering to apply it prints directly underneath. That is a true
        /// statement and useless advice, and it is what a misnamed file of recorded answers produced
        /// before that was refused — but it is reachable without any of that, by a skill whose tests all
        /// fail before and after.
        ///
        /// This does **not** change the verdict: nothing did get worse, and saying otherwise would refuse
        /// edits on grounds nobody asked for. It says what the verdict rests on, on the line above the
        /// suggestion to act on it.
        public var noPassingEvidenceDisclosure: Disclosure? {
            let measured = rows.filter(\.measured)
            let nonePassed = measured.allSatisfy { row in
                (row.before?.passes ?? 0) == 0 && (row.after?.passes ?? 0) == 0
            }
            guard !measured.isEmpty, nonePassed else { return nil }
            return Disclosure(
                subject: "nothing passed",
                reason: "not one check passed in either measurement, so \"no test scored lower\" only "
                    + "means nothing could — there is no evidence here that the edit helps")
        }

        /// **The omission, in words, or nothing when there is none.** Dropping a test from the average is
        /// the right call and still an omission, and an omission a reader cannot see is what this list
        /// exists to prevent. Built here rather than at the point it is printed so it can be checked: the
        /// route to it is closed further up — a test with no instruction to send is refused before
        /// anything is spent, and both measurements run the same list — so this would otherwise be
        /// unexercised prose that the next change to either guard silently inherits.
        public var unmeasuredDisclosure: Disclosure? {
            guard !unmeasured.isEmpty else { return nil }
            let names = unmeasured.map(\.id).joined(separator: ", ")
            let one = unmeasured.count == 1
            return Disclosure(
                subject: "not measured",
                reason: "\(names) recorded no runs in either measurement, so \(one ? "it is" : "they are") "
                    + "left out of the average change — the table above still shows \(one ? "it" : "them")")
        }
        /// Mean of the per-test differences.
        public let meanDelta: Double
        /// Its standard error — **absent below two comparable tests**, never a fabricated zero.
        public let standardError: Double?
        public var regressions: [Row] { rows.filter(\.regressed) }
        public var improvements: [Row] { rows.filter(\.improved) }
        /// The whole gate: nothing scored lower.
        public var proven: Bool { regressions.isEmpty }
    }

    /// Printed with every verdict. The check that measures how often the automatic grader agrees with a
    /// person has not shipped, so calling anything here proven is provisional — and saying so is the
    /// honest alternative to a statistical threshold resting on an error rate nobody has measured.
    public static let provisionalNote =
        "provisional — how often the grader agrees with a person has not been measured yet"

    /// **Takes sets in which no two tests share a name**, so there is nothing here to decide about a
    /// repeat. This used to build its own lookup keeping the first entry for a name and discarding the
    /// rest, which meant a second test of the same name — and any regression it carried — vanished from
    /// the comparison without a word.
    public static func compare(before: UniqueByName<Measurement>,
                               after: UniqueByName<Measurement>) -> Outcome {
        // **Every test from either side.** A test that disappears is compared against zero rather than
        // skipped, so removing a passing test cannot read as "nothing got worse".
        let ids = Set(before.names).union(after.names).sorted()
        let rows = ids.map { id -> Row in
            let b = before[id], a = after[id]
            return Row(id: id, before: b, after: a,
                       delta: (a?.rate ?? 0) - (b?.rate ?? 0),
                       noisy: b?.status == .flaky || a?.status == .flaky)
        }
        // **The average is over what was measured.** A test that ran on neither side contributes a
        // difference of exactly zero by construction — not because it did not change, but because nothing
        // asked it to. Left in, it pulls the headline toward zero and invents spread: one real
        // improvement of `+1.00` beside one non-measurement printed as `+0.50 ± 0.50`, which reads as a
        // smaller, shakier result than the run actually produced.
        //
        // **The blocking rule is untouched by this.** Whether an edit is refused is decided row by row —
        // any test scoring lower blocks — so a test that vanished still shows its drop and still blocks,
        // whatever the average does. And it stays *in* the average, because one side of it was measured.
        let stats = PairedDifference.summarize(rows.filter(\.measured).map(\.delta))
        return Outcome(rows: rows, meanDelta: stats.mean, standardError: stats.se)
    }
}
