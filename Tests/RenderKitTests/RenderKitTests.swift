import Testing
import EDDCore
import RenderKit

/// A name cut to fit a column must never look like the whole name — two evals sharing a long prefix
/// printed as the same row, with nothing to tell them apart.
@Suite("renderIterate — eval names fit or are visibly shortened")
struct IterateColumnTests {
    private func report(_ ids: [String]) -> IterateReport {
        IterateReport(skill: "demo", proposals: "fix.json", edits: [0], proven: true,
                      comparison: .init(
                        perEval: ids.map { .init(id: $0, beforePasses: 0, beforeRecorded: 1,
                                                 afterPasses: 1, afterRecorded: 1, delta: 1, noisy: false) },
                        meanDelta: 1, standardError: nil, improved: 1, regressed: 0))
    }

    private func rendered(_ ids: [String]) throws -> String {
        try Renderer(mode: .human, color: ColorPolicy(enabled: false))
            .renderIterate(report(ids), keptCopy: nil, landCommand: "x").stdout
    }

    @Test("A name longer than the default column is shown in full when it can be")
    func longNameShownWhole() throws {
        let id = "a-name-that-is-longer-than-the-old-column"     // 41 characters
        #expect(try rendered([id]).contains(id), "it fits inside the bound, so nothing is lost")
    }

    @Test("Two names sharing a long prefix stay distinguishable")
    func sharedPrefixesStayApart() throws {
        let out = try rendered(["produces-the-report-for-quarter-one",
                                "produces-the-report-for-quarter-two"])
        #expect(out.contains("quarter-one") && out.contains("quarter-two"),
                "if either were cut at the shared prefix the two rows would read identically")
    }

    @Test("A name past the bound is shortened with a mark, never silently")
    func pastTheBoundIsMarked() throws {
        let id = String(repeating: "x", count: 80)
        let out = try rendered([id])
        #expect(out.contains("…"), "a cut name must announce that it was cut")
        #expect(!out.contains(id), "and must not claim to be the whole name")
    }
}

/// A difference too small to print at two decimal places is still a difference. Rounding used to turn
/// one into `+0.00 ▲` — a number reading as nothing beside an arrow saying otherwise.
@Suite("renderIterate — a change too small to show says so")
struct IterateTinyDeltaTests {
    /// The row for the eval, not the whole table — the summary line beneath carries its own figure.
    private func row(delta: Double) throws -> String {
        try rendered(delta: delta).split(separator: "\n").first { $0.contains("  e  ") || $0.hasPrefix("  e") && $0.contains("/") } .map(String.init) ?? ""
    }

    private func rendered(delta: Double) throws -> String {
        let report = IterateReport(
            skill: "demo", proposals: "fix.json", edits: [0], proven: delta >= 0,
            comparison: .init(perEval: [.init(id: "e", beforePasses: 0, beforeRecorded: 1000,
                                              afterPasses: 4, afterRecorded: 1000,
                                              delta: delta, noisy: false)],
                              meanDelta: delta, standardError: nil,
                              improved: delta > 0 ? 1 : 0, regressed: delta < 0 ? 1 : 0))
        return try Renderer(mode: .human, color: ColorPolicy(enabled: false))
            .renderIterate(report, keptCopy: nil, landCommand: "x").stdout
    }

    @Test("A tiny rise is not printed as zero")
    func tinyRise() throws {
        let out = try row(delta: 0.004)
        #expect(!out.contains("+0.00"), "a real rise must not read as no change")
        #expect(out.contains("<+0.01") && out.contains("▲"))
    }

    @Test("A tiny drop is not printed as zero")
    func tinyDrop() throws {
        let out = try row(delta: -0.004)
        #expect(!out.contains("-0.00"), "a real drop must not read as no change")
        #expect(out.contains(">-0.01") && out.contains("▼"))
    }

    @Test("Genuinely no change still shows a dash and no arrow")
    func exactlyZero() throws {
        let out = try row(delta: 0)
        #expect(out.contains("—"))
        #expect(!out.contains("▲") && !out.contains("▼"))
    }

    @Test("A difference large enough to show is shown as itself")
    func ordinaryDelta() throws {
        #expect(try row(delta: 0.25).contains("+0.25"))
    }
}

/// **The summary line shows the token difference, and a dash only when there is none.**
///
/// It printed a dash whatever had happened, while the saved file beside it recorded a real figure. A dash
/// has to mean "neither side counted anything", not "this tool does not report that".
@Suite("The comparison summary shows what was counted")
struct AbFooterTokenTests {
    private func rendered(tokenDelta: Double?) throws -> String {
        let ab = ABComparison(
            pairs: [(id: "a", withPasses: 1, withRecorded: 1, basePasses: 0, baseRecorded: 1)],
            timeDeltaSeconds: 0.5, polluted: 0, tokenDeltaPerAttempt: tokenDelta)
        let report = RunReport(skill: "demo", counts: [EvalCounts(id: "a", passes: 1, graded: 1)], ab: ab)
        return try Renderer(mode: .human, color: ColorPolicy(enabled: false))
            .renderRun(report, nextSteps: []).stdout
    }

    @Test("A counted difference is shown as a signed number")
    func countedDifferenceShown() throws {
        #expect(try rendered(tokenDelta: 500).contains("tokens Δ +500"))
    }

    @Test("A difference in the other direction keeps its sign")
    func negativeDifferenceShown() throws {
        #expect(try rendered(tokenDelta: -120).contains("tokens Δ -120"))
    }

    /// **The two halves of the summary line describe the same tests.** The average leaves out tests that
    /// ran on neither side; the repeat count beside it used to include them, so one measured test paired
    /// with one that never ran printed a real average of `+1.00` next to `observed k=0`.
    @Test("A measured test beside one that never ran reports the measured repeats")
    func mixedRowsReportMeasuredRepeats() throws {
        let rows = [
            IterateReport.Comparison.Row(id: "measured", beforePasses: 0, beforeRecorded: 3,
                                         afterPasses: 3, afterRecorded: 3, delta: 1.0, noisy: false),
            IterateReport.Comparison.Row(id: "never-ran", beforePasses: 0, beforeRecorded: 0,
                                         afterPasses: 0, afterRecorded: 0, delta: 0.0, noisy: false)
        ]
        let report = IterateReport(skill: "demo", proposals: "fix.json", edits: [0], proven: true,
                                   comparison: .init(perEval: rows, meanDelta: 1.0, standardError: nil,
                                                     improved: 1, regressed: 0))
        let line = try Renderer(mode: .human, color: ColorPolicy(enabled: false))
            .renderIterate(report, keptCopy: nil, landCommand: "x").stdout
            .split(separator: "\n").first { $0.contains("average change") }.map(String.init) ?? ""
        #expect(line.contains("(observed k=3)"),
                "the average is drawn from the test that ran, so the count must be too: \(line)")
        #expect(line.contains("+1.00"), "and the average it sits beside is still stated")
    }

    @Test("Nothing counted still shows a dash")
    func uncountedShowsDash() throws {
        #expect(try rendered(tokenDelta: nil).contains("tokens Δ —"))
    }
}
