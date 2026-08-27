import Testing
import Foundation
import EDDCore
@testable import RenderKit

/// **What is printed when a test recorded no runs at all.**
///
/// A test with no instruction to send cannot be run, and a test can exist before an edit and be gone
/// after it. Either way it records nothing, and its counts read `0/0` — indistinguishable, on the page,
/// from a test that ran and scored zero. The summary line printed an average and a spread over it anyway,
/// beside a repeat count of zero: a confident-looking result whose own caveat said nothing had run.
///
/// The command that measures a skill already refuses to state its headline figure in this situation and
/// says the word "unmeasurable" instead. This one did not, which is the same rule applied in one place
/// and quietly missing from its neighbour.
@Suite("The summary refuses to average over tests that never ran")
struct IterateUnmeasuredTests {
    private func rendered(_ rows: [(id: String, recorded: Int, delta: Double)]) throws -> String {
        let report = IterateReport(
            skill: "demo", proposals: "fix.json", edits: [0], proven: true,
            comparison: .init(
                perEval: rows.map {
                    .init(id: $0.id, beforePasses: 0, beforeRecorded: $0.recorded,
                          afterPasses: $0.recorded, afterRecorded: $0.recorded,
                          delta: $0.delta, noisy: false)
                },
                meanDelta: 0, standardError: nil, improved: 0, regressed: 0))
        return try Renderer(mode: .human, color: ColorPolicy(enabled: false))
            .renderIterate(report, keptCopy: nil, landCommand: "x").stdout
    }

    private func summary(_ text: String) -> String {
        text.split(separator: "\n").first { $0.contains("average change") }.map(String.init) ?? ""
    }

    @Test("With nothing measured anywhere, no average is stated")
    func nothingMeasured() throws {
        let line = summary(try rendered([("a", 0, 0), ("b", 0, 0)]))
        #expect(line.contains("unmeasurable"),
                "the same word the measuring command uses when its own figure would rest on nothing")
        #expect(!line.contains("+0.00"),
                "an average of zero over nothing reads as 'measured, and unchanged' — it was neither")
    }

    /// The other half, so the guard above cannot be satisfied by never printing an average: a run that
    /// measured something still states its figure exactly as before.
    @Test("With something measured, the average is stated as before")
    func somethingMeasured() throws {
        let line = summary(try rendered([("a", 3, 0)]))
        #expect(line.contains("+0.00"), "a measured change of zero is a real result and is shown")
        #expect(!line.contains("unmeasurable"))
    }

    /// One measured test beside one that never ran is enough: the average rests on the measured one.
    @Test("One measured test among unmeasured ones is enough to state an average")
    func oneMeasuredIsEnough() throws {
        let line = summary(try rendered([("ran", 3, 0), ("never", 0, 0)]))
        #expect(!line.contains("unmeasurable"))
    }

    /// The rows themselves are untouched — a reader has to be able to see that the test exists and that
    /// nothing ran for it. Hiding it would trade one confusion for a worse one.
    @Test("A test that never ran is still shown in the table")
    func unmeasuredRowStillShown() throws {
        let text = try rendered([("ran", 3, 0), ("never", 0, 0)])
        #expect(text.contains("never"), "it is still in the table")
        #expect(text.contains("0/0"), "showing plainly that nothing ran for it")
    }
}
