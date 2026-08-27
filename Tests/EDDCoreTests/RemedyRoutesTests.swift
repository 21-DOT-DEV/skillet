import Testing
import Foundation
@testable import EDDCore

/// Every fix an error suggests must be one that exists.
///
/// The message shown when a program cannot be found used to open with `--harness-path`, a switch no
/// command accepts — so the first thing it offered someone already stuck was a route that was never
/// built. That flag is the top of the documented resolution chain (`skillet-design.md:895`) and is
/// tracked as work to do; until it exists, no message may name it.
@Suite("Error remedies name only routes that exist")
struct RemedyRoutesTests {
    /// Switches that no command declares today. Delete an entry here when the switch is built, and this
    /// test stops objecting to messages that name it.
    static let notBuilt = ["--harness-path"]

    @Test("No remedy suggests a switch that does not exist", arguments: [
        EDDError.harnessNotFound(harness: "claude-code", reason: nil),
        EDDError.harnessNotFound(harness: "git", reason: nil),
        EDDError.harnessUnauthenticated(harness: "claude-code"),
        EDDError.harnessBanned(harness: "claude-code", version: "1.0.0")
    ])
    func remedyNamesOnlyRealRoutes(_ error: EDDError) {
        for phantom in Self.notBuilt {
            #expect(!error.remedy.contains(phantom),
                    "the fix for \(error.kind) offers \(phantom), which no command accepts")
        }
    }

    /// The two routes that *do* exist stay named, so removing the phantom did not quietly remove the help.
    @Test("The routes that exist are still offered")
    func realRoutesStayNamed() {
        let remedy = EDDError.harnessNotFound(harness: "claude-code", reason: nil).remedy
        #expect(remedy.contains("SKILLET_CLAUDE_CODE_BIN"), "the environment variable route")
        #expect(remedy.contains("harness.claude-code.path"), "the configuration-file route")
    }
}
