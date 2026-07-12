import Testing
import Foundation
@testable import EDDCore

@Suite("Evidence — lifecycle, validation, flattening codec (F29)")
struct EvidenceTests {
    private func header(state: LifecycleState = .logged, id: String = "2026-06-07-snippets-dont-compile",
                        stateReason: String? = nil) -> EvidenceHeader {
        EvidenceHeader(id: id, skill: "docc-articles", domain: "secp256k1", lever: .eval, state: state,
                       stateReason: stateReason, sessions: ["2026-06-01-secp-sign"],
                       skillVersion: "1.3.0", model: "claude-opus-4-8")
    }

    // MARK: - Lifecycle (D1)

    @Test func forwardAndSideEdgesAreLegal() {
        #expect(EvidenceLifecycle.canTransition(from: .logged, to: .candidate))
        #expect(EvidenceLifecycle.canTransition(from: .candidate, to: .codified))
        #expect(EvidenceLifecycle.canTransition(from: .codified, to: .proven))
        #expect(EvidenceLifecycle.canTransition(from: .proven, to: .closed))
        #expect(EvidenceLifecycle.canTransition(from: .logged, to: .held))    // enter a side state
        #expect(EvidenceLifecycle.canTransition(from: .held, to: .candidate)) // leave it
    }

    @Test func reopenIsTheOneBackwardEdge() {
        #expect(EvidenceLifecycle.canTransition(from: .closed, to: .logged))       // reopen (Unknown 1)
    }

    @Test func illegalEdgesRejected() {
        #expect(!EvidenceLifecycle.canTransition(from: .logged, to: .proven))      // no skipping
        #expect(!EvidenceLifecycle.canTransition(from: .watch, to: .held))         // no direct side-swap
        #expect(!EvidenceLifecycle.canTransition(from: .proven, to: .logged))      // no revert
        #expect(!EvidenceLifecycle.canTransition(from: .closed, to: .candidate))   // reopen goes only to logged
    }

    @Test func selfTransitionAlwaysRejected() {
        for s in LifecycleState.allCases { #expect(!EvidenceLifecycle.canTransition(from: s, to: s)) }
    }

    @Test func validateThrowsIllegalTransition() {
        #expect(throws: EvidenceError.illegalTransition(from: .logged, to: .proven)) {
            try EvidenceLifecycle.validate(from: .logged, to: .proven)
        }
    }

    // MARK: - Validation (D5, F4)

    @Test func validRecordPasses() throws { try FrictionEvent(header: header()).validate() }

    @Test func malformedIdRejected() {
        #expect(throws: EvidenceError.self) { try FrictionEvent(header: header(id: "not a valid id")).validate() }
        #expect(throws: EvidenceError.self) { try FrictionEvent(header: header(id: "snippets-only")).validate() }
    }

    @Test func heldWatchClosedRequireANonEmptyReason() {
        for st in [LifecycleState.held, .watch, .closed] {
            #expect(throws: EvidenceError.missingStateReason(state: st)) {
                try FrictionEvent(header: header(state: st, stateReason: nil)).validate()
            }
            #expect(throws: EvidenceError.missingStateReason(state: st)) {
                try FrictionEvent(header: header(state: st, stateReason: "   ")).validate()   // whitespace ⇒ empty
            }
        }
    }

    @Test func heldWithReasonPasses() throws {
        try FrictionEvent(header: header(state: .held, stateReason: "single-domain; only lever is compile-eval")).validate()
    }

    @Test func pipelineStatesDontRequireReason() throws {
        for st in [LifecycleState.logged, .candidate, .codified, .proven] {
            try FrictionEvent(header: header(state: st)).validate()
        }
    }

    @Test func filenameStemMustMatchId() throws {
        let ev = FrictionEvent(header: header(id: "2026-06-07-snippets-dont-compile"))
        try ev.validate(filename: "2026-06-07-snippets-dont-compile.md")           // matches → ok
        #expect(throws: EvidenceError.self) { try ev.validate(filename: "2026-06-07-other.md") }
    }

    // MARK: - Flattening codec (JSON — pure; validates the flatten independent of YAML)

    @Test func frictionRoundTripsFlatViaJSON() throws {
        let ev = FrictionEvent(header: header(state: .held, stateReason: "single-domain"))
        let data = try JSONEncoder().encode(ev)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("skillet.friction"))  // (JSON escapes the "/1"; the decode below proves the exact tag)
        #expect(json.contains("\"id\""))            // header flattened to the top level…
        #expect(!json.contains("\"header\""))       // …not nested under a `header` key
        #expect(try JSONDecoder().decode(FrictionEvent.self, from: data) == ev)
    }

    @Test func findingRoundTripsWithItsFields() throws {
        let f = Finding(header: header(), source: .scorer, confidence: .high, cluster: "rule-of-three", signal: "density<0.4")
        let data = try JSONEncoder().encode(f)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("skillet.finding"))   // (JSON escapes the "/1"; the decode below proves the exact tag)
        #expect(try JSONDecoder().decode(Finding.self, from: data) == f)
    }

    @Test func absentOptionalAndSentinelFieldsTakeTheirDefaults() throws {
        let json = #"{"id":"2026-06-07-x","skill":"s","domain":"d","lever":"eval","state":"logged"}"#
        let h = try JSONDecoder().decode(EvidenceHeader.self, from: Data(json.utf8))
        #expect(h.sessions == [])
        #expect(h.skillVersion == "unknown")
        #expect(h.model == "unknown")
        #expect(h.stateReason == nil)
    }
}
