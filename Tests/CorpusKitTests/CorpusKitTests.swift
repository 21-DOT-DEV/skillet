import Testing
import Foundation
import TraceKit
@testable import CorpusKit

@Suite("CorpusKit — BundleText, Redactable, Sanitizer")
struct CorpusKitCoreTests {
    private func sampleTrace(toolInput: String) -> Trace {
        Trace(
            harness: "claude-code", harnessVersion: "1.0",
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1),
            turns: [
                Turn(role: .user, text: "please deploy", at: Date(timeIntervalSince1970: 0)),
                Turn(role: .assistant, text: "running", toolCalls: [ToolCall(name: "Bash", input: toolInput)],
                     filesTouched: ["a.txt"], at: Date(timeIntervalSince1970: 1)),
            ],
            skillInvocations: [SkillInvocation(skill: "docc-articles", turnIndex: 1)],
            workspaceDiff: WorkspaceDiff(added: ["a.txt"]))
    }

    @Test("redacting scrubs toolCall.input (the tool-argument leak vector) and re-encodes valid JSON")
    func redactsToolInput() throws {
        let secret = "ghp_SECRET"
        let bundle = BundleText(
            transcript: "used \(secret)", diff: "diff \(secret)",
            bodies: ["x.md": "body \(secret)"],
            trace: sampleTrace(toolInput: "curl -H 'token: \(secret)'"))
        let redacted = bundle.redacting { $0.replacingOccurrences(of: secret, with: "[REDACTED:x]") }

        #expect(!redacted.transcript.contains(secret))
        #expect(!redacted.diff.contains(secret))
        #expect(!redacted.bodies["x.md"]!.contains(secret))
        let toolInput = try #require(redacted.trace.turns[1].toolCalls[0].input)
        #expect(!toolInput.contains(secret))
        #expect(toolInput.contains("[REDACTED:x]"))

        // Re-encodes to valid trace.json, still round-trips, and holds no raw secret.
        let data = try JSONEncoder().encode(redacted.trace)
        #expect(try JSONDecoder().decode(Trace.self, from: data) == redacted.trace)
        #expect(!String(data: data, encoding: .utf8)!.contains(secret))
    }

    @Test("scanInputs labels each artifact with a path and includes trace text")
    func scanInputsLabeled() throws {
        let bundle = BundleText(transcript: "t", diff: "d", bodies: ["b.md": "body"],
                                trace: sampleTrace(toolInput: "cmd-arg"))
        let inputs = bundle.scanInputs
        let paths = Set(inputs.map(\.path))
        #expect(paths.isSuperset(of: ["transcript.md", "diff", "b.md", "trace.json"]))
        let traceBlob = try #require(inputs.first { $0.path == "trace.json" }).text
        #expect(traceBlob.contains("cmd-arg"))   // tool argument reaches the scanner
    }

    @Test("scanInputs scans each body key under its REAL path (not synthetic 'paths') + trace path fields")
    func scanInputsCoversPaths() {
        let bundle = BundleText(transcript: "t", diff: "d",
                                bodies: ["ghp_KEYSECRET.md": "clean"],
                                trace: sampleTrace(toolInput: "cmd"))
        let inputs = bundle.scanInputs
        // The body's key is scanned under its real path label → a filename finding carries the real path
        // (exemptable), and there's no synthetic "paths" label users can't target.
        #expect(inputs.first { $0.path == "ghp_KEYSECRET.md" }?.text.contains("ghp_KEYSECRET.md") == true)
        #expect(inputs.contains { $0.path == "paths" } == false)
        let traceBlob = inputs.first { $0.path == "trace.json" }?.text ?? ""
        #expect(traceBlob.contains("a.txt"))                     // filesTouched / workspaceDiff path scanned
        #expect(traceBlob.contains("docc-articles"))             // skillInvocations.skill scanned
    }

    @Test("redacting scrubs body KEYS, not just values — a secret in a filename can't survive as a key")
    func redactingScrubsKeys() {
        let bundle = BundleText(transcript: "", diff: "", bodies: ["ghp_SECRET.md": "clean body"],
                                trace: sampleTrace(toolInput: "c"))
        let redacted = bundle.redacting { $0.replacingOccurrences(of: "ghp_SECRET", with: "[REDACTED:x]") }
        #expect(redacted.bodies["[REDACTED:x].md"] == "clean body")   // key scrubbed, value preserved
        #expect(redacted.bodies["ghp_SECRET.md"] == nil)              // raw key is gone
    }

    @Test("Two paths that redact to the same key are disambiguated — no body silently overwritten")
    func redactingDisambiguatesKeyCollision() {
        let bundle = BundleText(transcript: "", diff: "",
                                bodies: ["ghp_a.txt": "body A", "ghp_b.txt": "body B"],
                                trace: sampleTrace(toolInput: "c"))
        // Both filenames scrub to `[REDACTED:gh].txt` — the collision case.
        let redacted = bundle.redacting {
            $0.replacingOccurrences(of: "ghp_a", with: "[REDACTED:gh]")
              .replacingOccurrences(of: "ghp_b", with: "[REDACTED:gh]")
        }
        #expect(redacted.bodies.count == 2)                              // neither body lost
        #expect(Set(redacted.bodies.values) == ["body A", "body B"])     // both values survive
        #expect(!redacted.bodies.keys.contains { $0.contains("ghp_") })  // no raw secret in any key
        #expect(redacted.bodies.keys.contains("[REDACTED:gh].txt"))      // first keeps the clean key
        #expect(redacted.bodies.keys.contains("[REDACTED:gh]-2.txt"))    // second disambiguated, extension kept
    }

    @Test("NoopSanitizer passes through unchanged, stamps scanner:none (test double only)")
    func noop() async throws {
        let bundle = BundleText(transcript: "x", diff: "d", bodies: [:], trace: sampleTrace(toolInput: "c"))
        let (redacted, report) = try await NoopSanitizer().sanitize(bundle)
        #expect(redacted == bundle)
        #expect(report.scanner == "none")
        #expect(report.summary["scanner"]?.stringValue == "none")
        #expect(report.summary["version"] == nil)   // absent when nil (no `disabled` field at all — R5)
    }
}
