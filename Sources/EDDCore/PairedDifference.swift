import Foundation

/// The one way this project turns a set of per-test before/after differences into a summary number and
/// an honest error bar.
///
/// **It lives on its own because two features depend on it.** It began inside the block that reports a
/// skill switched on versus off, which was the only caller; the command that proves an edit needs the
/// same statistic for a different pair, and a reader of that command should not have to call something
/// named for the other comparison to get a general result. Nothing about the maths changed in the move —
/// the old name still works and forwards here, so anything already calling it is unaffected.
///
/// **Why pair at all.** Each test has its own difficulty, and pairing cancels it: the difference is taken
/// per test and those differences are averaged. Subtracting two overall scores instead would mix the
/// change you care about with which tests happen to be hard.
public enum PairedDifference {
    /// The mean of the per-test differences, and a standard error when there are at least two of them.
    ///
    /// **Below two, the error bar is absent rather than invented.** One difference tells you nothing
    /// about spread, and a made-up zero would read as certainty. Callers show "too few to state
    /// uncertainty" instead.
    public static func summarize(_ deltas: [Double]) -> (mean: Double, se: Double?) {
        guard !deltas.isEmpty else { return (0, nil) }
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        guard deltas.count >= 2 else { return (mean, nil) }
        let variance = deltas.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(deltas.count - 1)
        return (mean, (variance / Double(deltas.count)).squareRoot())
    }
}
