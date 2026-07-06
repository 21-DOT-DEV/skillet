import Testing
import EDDCore
@testable import HarnessKit

/// F14 (A1): the live `claude -p --output-format stream-json` shape — assistant events wrapping
/// `message.content[]` blocks (predecessor `StreamEventTests` fixture grammar) — must yield
/// `skillInvocations` for `Skill` tool_use blocks, since the trigger axis grades on exactly that.
@Suite("Live stream-json Skill-invocation parsing (trigger axis)")
struct TriggerParseTests {
    @Test("A live-shape assistant event with a Skill tool_use parses to a skill invocation")
    func liveShapeSkillInvocation() {
        let live = """
        {"type":"system","subtype":"init","session_id":"s"}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Using the skill."},{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"demo"}}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}
        {"type":"result","subtype":"success","result":"done"}
        """
        let trace = ClaudeCodeAdapter.parse(jsonl: live)
        #expect(trace.skillInvocations.map(\.skill) == ["demo"])
        #expect(trace.turns.count == 2)
    }

    @Test("A live-shape run with no Skill blocks parses to zero invocations (deterministic not-fired)")
    func liveShapeNoInvocation() {
        let live = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"plain answer"}]}}
        """
        let trace = ClaudeCodeAdapter.parse(jsonl: live)
        #expect(trace.skillInvocations.isEmpty)
    }
}
