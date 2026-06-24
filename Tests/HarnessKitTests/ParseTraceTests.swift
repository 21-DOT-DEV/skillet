import Testing
import EDDCore
import TraceKit
import HarnessKit

@Suite("claude-code trace parsing")
struct ParseTraceTests {
    // A synthetic session mirroring the real ~/.claude JSONL shape — NOT a committed real log
    // (constitution VI). Faithfulness to the live format is what makes F7's live parse work. In the
    // native format every tool call emits a `user` `tool_result` line carrying a `toolUseResult`
    // (the authoritative result), interleaved with `thinking`/`text` assistant lines and control
    // lines (`ai-title`, etc.). Real user turns carry `text`.
    let synthetic = """
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"add a greeting"},{"type":"text","text":"please"}]},"timestamp":"2026-01-01T00:00:00Z","version":"2.1.146"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Using a skill."},{"type":"tool_use","name":"Skill","input":{"skill":"docc-articles","args":""}}]},"timestamp":"2026-01-01T00:00:05Z","version":"2.1.146"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"greeting.txt","content":"hi"}}]},"timestamp":"2026-01-01T00:00:10Z","version":"2.1.146"}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"timestamp":"2026-01-01T00:00:11Z","version":"2.1.146","toolUseResult":{"type":"create","filePath":"greeting.txt"}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"README.md","old_string":"a","new_string":"b"}}]},"timestamp":"2026-01-01T00:00:15Z","version":"2.1.146"}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"ok"}]},"timestamp":"2026-01-01T00:00:16Z","version":"2.1.146","toolUseResult":{"type":"update","filePath":"README.md"}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]},"timestamp":"2026-01-01T00:00:20Z","version":"2.1.146"}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t3","content":"greeting.txt"}]},"timestamp":"2026-01-01T00:00:21Z","version":"2.1.146","toolUseResult":{"type":"text","stdout":"greeting.txt"}}
    {"type":"ai-title","aiTitle":"add a greeting","sessionId":"s1"}
    """

    func parsed() throws -> Trace {
        try ClaudeCodeAdapter().parseTrace(RawTrace(harness: "claude-code", raw: synthetic))
    }

    @Test("Real turns only: assistant lines + user lines with text; tool-result lines aren't turns")
    func turns() throws {
        let trace = try parsed()
        #expect(trace.harness == "claude-code")
        #expect(trace.harnessVersion == "2.1.146")
        // 9 lines: 1 user-text + 4 assistant turns = 5 turns; 3 tool_result lines + 1 ai-title dropped.
        #expect(trace.turns.count == 5)
        #expect(trace.turns[0].role == .user)
        #expect(trace.turns.dropFirst().allSatisfy { $0.role == .assistant })
        #expect(trace.startedAt < trace.endedAt)
    }

    @Test("Multiple text blocks in one turn are joined with a newline")
    func joinsTextBlocks() throws {
        #expect(try parsed().turns[0].text == "add a greeting\nplease")
    }

    @Test("A Skill tool_use becomes a skill invocation at its turn")
    func skillInvocation() throws {
        let trace = try parsed()
        #expect(trace.skillInvocations == [SkillInvocation(skill: "docc-articles", turnIndex: 1)])
        #expect(trace.turns[1].toolCalls.contains { $0.name == "Skill" })
    }

    @Test("Workspace diff comes from toolUseResult (create→added, update→modified)")
    func workspaceDiff() throws {
        let trace = try parsed()
        #expect(trace.workspaceDiff.added == ["greeting.txt"])      // create result
        #expect(trace.workspaceDiff.modified == ["README.md"])      // update result
        #expect(trace.workspaceDiff.deleted == [])                  // deletions not modeled (F6 gap)
        // Per-turn provenance still comes from the request input.
        #expect(trace.turns[2].filesTouched == ["greeting.txt"])
        #expect(trace.turns[3].filesTouched == ["README.md"])
    }

    @Test("A non-file tool result (type text) contributes no file change")
    func nonFileResultIgnored() throws {
        let trace = try parsed()
        // Only the create + update results count; the `type:text` Bash result adds nothing.
        #expect(trace.workspaceDiff.added.count == 1)
        #expect(trace.workspaceDiff.modified.count == 1)
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
