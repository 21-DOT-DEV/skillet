import Testing
import Foundation
import TraceKit
@testable import CorpusKit

@Suite("TranscriptRenderer")
struct TranscriptRendererTests {
    @Test("Renders familiar ## User / ## Assistant / **Tool Call:** headers")
    func rendersHeaders() {
        let trace = Trace(
            harness: "claude-code", harnessVersion: "1",
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1),
            turns: [
                Turn(role: .user, text: "fix the imports", at: Date(timeIntervalSince1970: 0)),
                Turn(role: .assistant, text: "on it",
                     toolCalls: [ToolCall(name: "Bash", input: "swift build")], at: Date(timeIntervalSince1970: 1)),
            ],
            skillInvocations: [], workspaceDiff: WorkspaceDiff())
        let md = TranscriptRenderer.render(trace)
        #expect(md.contains("## User\n\nfix the imports"))
        #expect(md.contains("## Assistant\n\non it"))
        #expect(md.contains("**Tool Call: Bash**"))
        #expect(md.contains("```\nswift build\n```"))
    }

    @Test("A tool call with no input renders just its header")
    func toolWithoutInput() {
        let trace = Trace(
            harness: "claude-code", harnessVersion: "1",
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 0),
            turns: [Turn(role: .assistant, text: "", toolCalls: [ToolCall(name: "Read")], at: Date(timeIntervalSince1970: 0))],
            skillInvocations: [], workspaceDiff: WorkspaceDiff())
        let md = TranscriptRenderer.render(trace)
        #expect(md.contains("**Tool Call: Read**"))
        #expect(!md.contains("```"))
    }
}
