import Testing
import Foundation
@testable import EDDCore

/// **Figures worked out from the rows are worked out again when a report is read back.**
///
/// Two fields say in their own descriptions that they cannot be supplied, only derived: how many repeats
/// were actually observed, and whether a given test ran at all. Both were stored values with a reader
/// written by the compiler, so both were simply taken from the text. Measured before this was closed: a
/// report built with nothing recorded said the repeats were none, and one edit to the saved text made it
/// read back as ninety-nine — with each row's "did this run" flag flipped to true while its own counts
/// still said nothing ran. The report then contradicted itself.
///
/// Nothing reads this format back today. That is why it was worth closing rather than leaving: the next
/// reader added — a test, a script, a migration — would have inherited it silently.
@Suite("Derived figures are re-derived when a report is read back")
struct DerivedFiguresSurviveReadingBackTests {
    private func report(beforeRecorded: Int, afterRecorded: Int) -> IterateReport {
        IterateReport(
            skill: "demo", proposals: "fix.json", edits: [0], proven: true,
            comparison: .init(
                perEval: [.init(id: "a", beforePasses: 0, beforeRecorded: beforeRecorded,
                                afterPasses: 0, afterRecorded: afterRecorded, delta: 0, noisy: false)],
                meanDelta: 0, standardError: nil, improved: 0, regressed: 0))
    }

    private func readBack(_ report: IterateReport, editing: [(String, String)]) throws -> IterateReport {
        var text = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        for (from, to) in editing { text = text.replacingOccurrences(of: from, with: to) }
        return try JSONDecoder().decode(IterateReport.self, from: Data(text.utf8))
    }

    @Test("Text claiming more repeats than the rows support does not change the figure")
    func repeatsCannotBeSupplied() throws {
        let back = try readBack(report(beforeRecorded: 0, afterRecorded: 0),
                                editing: [("\"observedK\":0", "\"observedK\":99")])
        #expect(back.observedK == 0, "no test ran, so no repeats were observed, whatever the text says")
    }

    @Test("Text claiming a test ran does not override its own counts")
    func measuredCannotBeSupplied() throws {
        let back = try readBack(report(beforeRecorded: 0, afterRecorded: 0),
                                editing: [("\"measured\":false", "\"measured\":true")])
        #expect(back.comparison.perEval[0].measured == false,
                "its own counts say nothing ran; the flag must agree with them")
    }

    @Test("An ordinary report still reads back exactly as it was written")
    func ordinaryReportRoundTrips() throws {
        let original = report(beforeRecorded: 3, afterRecorded: 3)
        let back = try readBack(original, editing: [])
        #expect(back.observedK == 3)
        #expect(back.comparison.perEval[0].measured)
        #expect(back == original, "nothing else changed shape")
    }
}
