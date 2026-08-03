import Foundation
import EDDCore
import HarnessKit

/// The one check every paid command must pass **before** it spends.
///
/// It refuses a model program that is a known-bad version, or one you are not signed in to — so the
/// failure arrives as a clear, free refusal instead of a confusing error part-way through a paid call.
///
/// **Why this is a single routine rather than a line in each command.** It previously lived only inside
/// the measured-run command; when the drafting command was added it simply forgot, so that command could
/// spend against a blocked or signed-out setup and the corresponding refusals were unreachable from it.
/// That is the textbook argument for one enforcement point: several implementations, most correct and one
/// flawed, is precisely the failure mode a single shared routine prevents — and every path to the same
/// operation must apply the same checks. A future paid command inherits this by calling one function.
enum SpendGate {
    /// Probe the harness and refuse if it is unusable. Returns the harness details, because a caller may
    /// also need them (the measured-run command stamps the version into its records).
    ///
    /// `strict` is what turns an auto-discovered bad version from a warning into a refusal; paid paths
    /// pass `true`. The measured-run command relaxes it only for its canned offline mode, which spends
    /// nothing.
    @discardableResult
    static func assertHarnessReady(_ adapter: any HarnessAdapter, strict: Bool = true) async throws -> HarnessInfo {
        try await adapter.probe(strict: strict)
    }
}
