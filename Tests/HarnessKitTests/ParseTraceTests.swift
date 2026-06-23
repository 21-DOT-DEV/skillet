import Testing
import EDDCore
import TraceKit
import HarnessKit

@Suite("claude-code trace parsing")
struct ParseTraceTests {
    // A synthetic session mirroring the real ~/.claude JSONL shape — NOT a committed real log
    // (constitution VI). Faithfulness to the live format is what makes F7's live parse work.
    let synthetic = """
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"add a greeting"}]},"timestamp":"2026-01-01T00:00:00Z","version":"2.1.146"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Using a skill."},{"type":"tool_use","name":"Skill","input":{"skill":"docc-articles","args":""}}]},"timestamp":"2026-01-01T00:00:05Z","version":"2.1.146"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"greeting.txt","content":"hi"}}]},"timestamp":"2026-01-01T00:00:10Z","version":"2.1.146"}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"timestamp":"2026-01-01T00:00:11Z","version":"2.1.146","toolUseResult":{"type":"create","filePath":"greeting.txt"}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"greeting.txt","old_string":"hi","new_string":"hello"}}]},"timestamp":"2026-01-01T00:00:15Z","version":"2.1.146"}
    {"type":"ai-title","aiTitle":"add a greeting","sessionId":"s1"}
    """

    func parsed() throws -> Trace {
        try ClaudeCodeAdapter().parseTrace(RawTrace(harness: "claude-code", raw: synthetic))
    }

    @Test("Maps user/assistant lines to turns, skipping control lines")
    func turns() throws {
        let trace = try parsed()
        #expect(trace.harness == "claude-code")
        #expect(trace.harnessVersion == "2.1.146")
        #expect(trace.turns.count == 5)         // 6 lines, the ai-title control line dropped
        #expect(trace.startedAt < trace.endedAt)
    }

    @Test("A Skill tool_use becomes a skill invocation at its turn")
    func skillInvocation() throws {
        let trace = try parsed()
        #expect(trace.skillInvocations == [SkillInvocation(skill: "docc-articles", turnIndex: 1)])
        #expect(trace.turns[1].toolCalls.contains { $0.name == "Skill" })
    }

    @Test("Write/Edit file paths feed the workspace diff and filesTouched")
    func workspaceDiff() throws {
        let trace = try parsed()
        #expect(trace.workspaceDiff.added == ["greeting.txt"])    // Write → added
        #expect(trace.workspaceDiff.modified == [])               // Edit of an added file isn't double-counted
        #expect(trace.workspaceDiff.deleted == [])
        #expect(trace.turns[2].filesTouched == ["greeting.txt"])
    }

    @Test("usage stays nil in v1 (deferred to v1.x)")
    func usageDeferred() throws {
        #expect(try parsed().usage == nil)
    }

    @Test("A malformed line is skipped, never fatal")
    func lenient() throws {
        let withGarbage = "not json\n" + synthetic
        let trace = try ClaudeCodeAdapter().parseTrace(RawTrace(harness: "claude-code", raw: withGarbage))
        #expect(trace.turns.count == 5)
    }
}
