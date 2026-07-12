import Testing
import Foundation
@testable import TraceKit

@Suite("CorrectiveTurns — recall-first detection")
struct CorrectiveTurnsTests {
    private func trace(_ turns: [Turn]) -> Trace {
        Trace(harness: "claude-code", harnessVersion: "1",
              startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1),
              turns: turns, skillInvocations: [], workspaceDiff: WorkspaceDiff())
    }
    private func user(_ text: String) -> Turn { Turn(role: .user, text: text, at: Date(timeIntervalSince1970: 0)) }
    private func assistant(_ text: String) -> Turn { Turn(role: .assistant, text: text, at: Date(timeIntervalSince1970: 0)) }

    @Test("Drops the opening prompt; keeps a substantive correction")
    func opensAndCorrects() {
        let t = trace([user("write the article"), assistant("done"), user("no, use the real API")])
        let found = CorrectiveTurns.detect(in: t)
        #expect(found.count == 1)
        #expect(found.first?.index == 1)
        #expect(found.first?.text == "no, use the real API")
    }

    @Test("Drops bare continuations (case/space tolerant)")
    func dropsContinuations() {
        let t = trace([user("start"), assistant("a"), user("continue"), assistant("b"), user("  GO ahead  ")])
        #expect(CorrectiveTurns.detect(in: t).isEmpty)
    }

    @Test("Drops empty user turns; ignores assistant turns")
    func dropsEmptyIgnoresAssistant() {
        let t = trace([user("open"), assistant("that is wrong"), user("   "), user("actually revert that")])
        let found = CorrectiveTurns.detect(in: t)
        #expect(found.count == 1)
        #expect(found.first?.text == "actually revert that")
        #expect(found.first?.index == 2)   // 0=open, 1=empty(dropped), 2=this
    }

    @Test("No user turns / only the opener → nothing")
    func degenerate() {
        #expect(CorrectiveTurns.detect(in: trace([])).isEmpty)
        #expect(CorrectiveTurns.detect(in: trace([user("just one prompt")])).isEmpty)
    }

    @Test("Multiple corrections all surface (recall-first)")
    func multiple() {
        let t = trace([user("go"), assistant("x"), user("fix the imports"), assistant("y"), user("and the tests")])
        let found = CorrectiveTurns.detect(in: t)
        #expect(found.map(\.text) == ["fix the imports", "and the tests"])
    }
}
