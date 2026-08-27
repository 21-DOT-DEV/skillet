import Testing
import Foundation
import EDDCore
import TraceKit

@Suite("Trace schema")
struct TraceTests {
    private func sampleTrace() -> Trace {
        Trace(
            harness: "replay",
            harnessVersion: "1.2.3",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_060),
            turns: [
                Turn(role: .user, text: "do it", at: Date(timeIntervalSince1970: 1_700_000_000)),
                Turn(
                    role: .assistant, text: "done",
                    toolCalls: [ToolCall(name: "write", input: "file.txt")],
                    filesTouched: ["file.txt"],
                    at: Date(timeIntervalSince1970: 1_700_000_030)
                )
            ],
            skillInvocations: [SkillInvocation(skill: "demo", turnIndex: 1)],
            workspaceDiff: WorkspaceDiff(added: ["file.txt"]),
            usage: nil
        )
    }

    @Test("Encodes with the skillet.trace/1 schema and snake_case keys")
    func encodesSchemaAndKeys() throws {
        let json = try SkilletJSON.encode(sampleTrace())
        #expect(json.contains(#""schema":"skillet.trace/1""#))
        #expect(json.contains(#""harness_version":"1.2.3""#))
        #expect(json.contains(#""skill_invocations":"#))
        #expect(json.contains(#""workspace_diff":"#))
        #expect(json.contains(#""turn_index":1"#))
        // **What this means is "no cost figures", not "no key containing the letters usage".** The looser
        // spelling caught an added field that says *why* figures are absent — which is the opposite of
        // what it was guarding. A diagnostic record is where being explicit is worth most, so that field
        // is stated rather than left to be inferred, and this now checks the thing it meant to check.
        #expect(!json.contains(#""usage":"#), "no cost figures were reported, so none are written")
        #expect(json.contains(#""usage_state":"absent""#),
                "and the record says that none were offered, rather than leaving a reader to work it out")
    }

    @Test("Round-trips through --json with the schema intact")
    func roundTrips() throws {
        let original = sampleTrace()
        let json = try SkilletJSON.encode(original)
        let decoded = try SkilletJSON.decode(Trace.self, from: json) // injected `schema` ignored on read
        #expect(decoded == original)
    }

    @Test("HarnessID encodes as a bare string")
    func harnessIDIsBareString() throws {
        let json = try SkilletJSON.encode(sampleTrace())
        #expect(json.contains(#""harness":"replay""#))
    }

    @Test("Dates use ISO-8601 UTC")
    func datesAreISO8601() throws {
        let json = try SkilletJSON.encode(sampleTrace())
        #expect(json.contains("2023-11-14T22:13:20Z")) // 1_700_000_000
    }
}
