import Foundation
import EDDCore

/// The gate on every hidden test-only option.
///
/// These options exist so the suite can run offline and free: one feeds a canned model reply from a
/// file, the others swap the real model and grader for offline stand-ins. They are hidden from `--help`,
/// but hidden is not the same as unavailable — they were real options on a real binary that any command
/// line could use. That is the "leftover debug code" weakness (CWE-489), and the two that read a file
/// were also reading **any** path on the machine, with no requirement to stay inside the project.
///
/// Two independent barriers, because each closes a different hole:
///
/// 1. **This variable must be set.** A crafted command line alone can no longer reach a seam. That
///    matters most for the offline switch, which replaces real grading with canned answers — anyone able
///    to slip it into an invocation could make a failing quality gate report success.
/// 2. **The reads are confined to the project** (at the call sites). Defence in depth, and the same rule
///    every other file read here already follows.
///
/// Compiling the seams out of release builds would be the strictest reading of the guidance, but the
/// suite runs the built binary — so that turns any release-mode test run into dozens of confusing
/// failures. A runtime gate keeps one binary that behaves the same way everywhere.
enum TestSeam {
    static let envVar = "SKILLET_TEST_SEAMS"

    /// Empty counts as unset, so a test can prove the refusal by passing an empty value (the harness
    /// overlays variables onto the parent environment and cannot remove one).
    static var isEnabled: Bool {
        !(ProcessInfo.processInfo.environment[envVar] ?? "").isEmpty
    }

    /// Refuse a hidden option that was not enabled. **Usage, not an internal error** — nothing is broken;
    /// the invocation asked for something that is not available, and the remedy is to drop the option.
    static func assertEnabled(_ option: String) throws {
        guard isEnabled else {
            throw EDDError.usage(
                message: "\(option) is a test-only option and is not available",
                remedy: "remove it — it exists so the test suite can run offline, "
                      + "and is honoured only when \(envVar) is set")
        }
    }
}
