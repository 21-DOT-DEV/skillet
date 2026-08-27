import Testing
import Foundation
import EDDCore
@testable import IterateKit

/// The verdict: given the same tests measured before and after an edit, is the edit safe to land?
///
/// Strict on purpose — any test scoring lower blocks, with no allowance for the drop being small. The
/// cost is lopsided: wrongly blocking a good edit costs a re-run, while wrongly calling a bad edit proven
/// puts a regression into a file you then commit. Noise is **shown, never excluded** (see `noisy`).
@Suite("The edit verdict")
struct EditVerdictTests {
    /// The comparison takes sets that cannot hold a repeated name, so each test builds one.
    private func unique(_ items: [EditVerdict.Measurement]) throws -> UniqueByName<EditVerdict.Measurement> {
        try UniqueByName(items, name: \.id)
    }

    /// `(id, passes, recorded)` → the shape the scoring math already takes.
    /// One measurement's results. Returns a set that cannot hold a repeated test name, because that is
    /// what the comparison takes — it no longer has a rule for what to do about a repeat.
    static func arm(_ rows: [(String, Int, Int)]) throws -> UniqueByName<EditVerdict.Measurement> {
        try UniqueByName(rows.map { EditVerdict.Measurement(id: $0.0, passes: $0.1, recorded: $0.2) },
                         name: \.id)
    }

    @Test("Nothing scored lower ⇒ proven")
    func nothingLowerIsProven() throws {
        let v = EditVerdict.compare(before: try Self.arm([("a", 1, 3), ("b", 3, 3)]),
                                    after: try Self.arm([("a", 3, 3), ("b", 3, 3)]))
        #expect(v.proven)
        #expect(v.regressions.isEmpty)
    }

    @Test("One test scored lower ⇒ blocked, and that test is named")
    func oneLowerBlocks() throws {
        let v = EditVerdict.compare(before: try Self.arm([("a", 3, 3), ("b", 3, 3)]),
                                    after: try Self.arm([("a", 3, 3), ("b", 1, 3)]))
        #expect(!v.proven)
        #expect(v.regressions.map(\.id) == ["b"])
    }

    /// A test that vanishes cannot hide a regression: it is compared against zero, not skipped.
    @Test("A test present in only one measurement is compared against zero")
    func vanishedTestCannotHide() throws {
        let v = EditVerdict.compare(before: try Self.arm([("a", 3, 3), ("gone", 3, 3)]),
                                    after: try Self.arm([("a", 3, 3)]))
        #expect(!v.proven, "dropping a passing test is a regression, not an absence")
        #expect(v.regressions.map(\.id) == ["gone"])
    }

    /// Blocking is not softened by noise — the drop is annotated so a reader can judge, and still blocks.
    @Test("A drop inside the error band still blocks, and is marked as sitting inside it")
    func noisyDropStillBlocks() throws {
        let v = EditVerdict.compare(before: try Self.arm([("a", 3, 3), ("b", 2, 3), ("c", 2, 3)]),
                                    after: try Self.arm([("a", 3, 3), ("b", 3, 3), ("c", 1, 3)]))
        #expect(!v.proven)
        let c = try #require(v.rows.first { $0.id == "c" })
        #expect(c.regressed)
        #expect(c.noisy, "this test swings between runs — say so rather than silently discounting it")
    }

    /// One difference tells you nothing about spread, and a fabricated zero would read as certainty.
    @Test("Below two comparable tests, the error bar is absent rather than invented")
    func tooFewForAnErrorBar() throws {
        let one = EditVerdict.compare(before: try Self.arm([("a", 1, 3)]), after: try Self.arm([("a", 3, 3)]))
        #expect(one.standardError == nil, "one difference cannot state uncertainty")
        let two = EditVerdict.compare(before: try Self.arm([("a", 1, 3), ("b", 1, 3)]),
                                      after: try Self.arm([("a", 3, 3), ("b", 2, 3)]))
        #expect(two.standardError != nil)
    }

    /// Until the check that measures how often the grader agrees with a person ships, the verdict is
    /// provisional and says so — the predecessor printed the same caveat for the same reason.
    /// A spread of zero is a **measured** answer and must read as one. The printed result says
    /// "± 0.00" for a measured zero and "too few evals to state uncertainty" when no spread can be
    /// computed at all — two different claims, and nothing pinned which one two identical differences
    /// produce.
    @Test("Two tests changing by the same amount give a stated spread of zero, not an absent one")
    func identicalDeltasGiveAMeasuredZeroSpread() throws {
        let before = [EditVerdict.Measurement(id: "a", passes: 1, recorded: 3),
                      EditVerdict.Measurement(id: "b", passes: 1, recorded: 3)]
        let after = [EditVerdict.Measurement(id: "a", passes: 3, recorded: 3),
                     EditVerdict.Measurement(id: "b", passes: 3, recorded: 3)]
        let outcome = EditVerdict.compare(before: try unique(before), after: try unique(after))
        #expect(outcome.standardError == 0, "both tests moved the same amount, so the spread is zero")
        #expect(outcome.standardError != nil, "zero is a measurement; absent means it could not be taken")
    }

    @Test("The verdict says it is provisional")
    func verdictIsProvisional() throws {
        #expect(EditVerdict.provisionalNote.lowercased().contains("provisional"))
    }
}

/// **An attempt that was never graded must not make a good edit look like a regression.**
///
/// This command decides whether an edit is kept. It compares each check's pass rate before and after the
/// edit, and any check that scores lower blocks it. Attempts that never produced a result — a rate limit,
/// a dropped connection, the model program falling over — used to count in the denominator as failures.
/// So a check that passed outright before, and after the edit had two graded attempts both passing plus
/// one never graded, read as a drop from 1.0 to 0.667 and **blocked the edit**. A network hiccup rejecting
/// someone's work is the wrong decision, taken from no evidence at all.
@Suite("An ungraded attempt does not turn a good edit into a regression")
struct UngradedAttemptDoesNotBlockAnEditTests {
    private func verdict(_ passed: Bool) -> Verdict {
        Verdict(criterion: "c", passed: passed, rationale: "", judgeId: "t", model: "m", judgePromptVersion: "1")
    }
    private func attempt(_ exit: TrialExit, passed: Bool) -> TrialResult {
        TrialResult(exit: exit, verdicts: exit == .error ? [] : [verdict(passed)])
    }

    @Test("Counts come from graded attempts, not from attempts made")
    func countsComeFromGradedAttempts() {
        let record = EvalResult(evalId: "a", trials: [
            attempt(.passed, passed: true), attempt(.passed, passed: true), attempt(.error, passed: false)])
        let measurement = EditVerdict.Measurement(record)
        #expect(measurement.passes == 2)
        #expect(measurement.recorded == 2, "two attempts produced a result; the third produced none")
    }

    @Test("A check that still passes, with one attempt ungraded, does not block the edit")
    func ungradedAttemptDoesNotBlock() throws {
        let before = try UniqueByName([EditVerdict.Measurement(
            EvalResult(evalId: "a", trials: [attempt(.passed, passed: true),
                                             attempt(.passed, passed: true),
                                             attempt(.passed, passed: true)]))], name: \.id)
        let after = try UniqueByName([EditVerdict.Measurement(
            EvalResult(evalId: "a", trials: [attempt(.passed, passed: true),
                                             attempt(.passed, passed: true),
                                             attempt(.error, passed: false)]))], name: \.id)
        let outcome = EditVerdict.compare(before: before, after: after)
        #expect(outcome.regressions.isEmpty, "every attempt that was graded passed, before and after")
        #expect(outcome.proven, "so nothing scored lower and the edit stands")
    }

    /// The other half, so this cannot be satisfied by never blocking anything.
    @Test("A check that genuinely got worse still blocks the edit")
    func realRegressionStillBlocks() throws {
        let before = try UniqueByName([EditVerdict.Measurement(
            EvalResult(evalId: "a", trials: [attempt(.passed, passed: true),
                                             attempt(.passed, passed: true)]))], name: \.id)
        let after = try UniqueByName([EditVerdict.Measurement(
            EvalResult(evalId: "a", trials: [attempt(.passed, passed: true),
                                             attempt(.failed, passed: false)]))], name: \.id)
        let outcome = EditVerdict.compare(before: before, after: after)
        #expect(outcome.regressions.map(\.id) == ["a"], "a graded attempt failed; that is a real drop")
        #expect(!outcome.proven)
    }
}
