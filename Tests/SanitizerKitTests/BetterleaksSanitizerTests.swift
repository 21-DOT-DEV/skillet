import Testing
import Foundation
import TraceKit
import CorpusKit
@testable import SanitizerKit

/// A scanner stub returning planted findings (no real betterleaks).
private struct StubScanner: SecretScanner {
    let findings: [Finding]
    func scan(_ inputs: [ScanInput]) async throws -> [Finding] { findings }
}

@Suite("BetterleaksSanitizer — scan + exempt + redact over BundleText")
struct BetterleaksSanitizerTests {
    private func bundle(_ text: String, toolInput: String) -> BundleText {
        let trace = Trace(
            harness: "claude-code", harnessVersion: "1",
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1),
            turns: [Turn(role: .assistant, text: text,
                         toolCalls: [ToolCall(name: "Bash", input: toolInput)], at: Date(timeIntervalSince1970: 0))],
            skillInvocations: [], workspaceDiff: WorkspaceDiff())
        return BundleText(transcript: text, diff: "diff \(text)", bodies: ["b.md": "body \(text)"], trace: trace)
    }

    @Test("Scrubs a detected secret across every artifact (value-based) and stamps provenance")
    func scrubsEverywhere() async throws {
        let secret = "ghp_SECRET"
        let scanner = StubScanner(findings: [Finding(ruleID: "github-pat", secret: secret, file: "transcript.md")])
        let s = BetterleaksSanitizer(scanner: scanner, version: "1.6.1")
        let (redacted, report) = try await s.sanitize(bundle("token \(secret)", toolInput: "curl -H 'x: \(secret)'"))

        #expect(!redacted.transcript.contains(secret))
        #expect(!redacted.diff.contains(secret))
        #expect(!redacted.bodies["b.md"]!.contains(secret))
        #expect(!(redacted.trace.turns[0].toolCalls[0].input ?? "").contains(secret))
        #expect(redacted.transcript.contains("[REDACTED:github-pat]"))
        #expect(report.scanner == "betterleaks")
        #expect(report.version == "1.6.1")
        #expect(report.redactions == 5)   // OCCURRENCES: transcript + diff + body value + trace text + trace tool-input
    }

    @Test("A blanket exempt_paths pattern (**) fails closed — never silently drops all findings")
    func blanketExemptFailsClosed() async {
        let scanner = StubScanner(findings: [Finding(ruleID: "gh", secret: "ghp_X", file: "transcript.md")])
        let s = BetterleaksSanitizer(scanner: scanner, exemptPaths: ["**"])
        await #expect(throws: SanitizerError.self) {   // refuses rather than writing an unredacted bundle
            _ = try await s.sanitize(bundle("token ghp_X", toolInput: "x"))
        }
    }

    @Test("Exempting a core synthetic artifact (transcript.md) fails closed — no --no-sanitize via config")
    func exemptSyntheticArtifactFailsClosed() async {
        let scanner = StubScanner(findings: [Finding(ruleID: "gh", secret: "ghp_X", file: "transcript.md")])
        for pattern in ["transcript.md", "diff", "trace.json", "**/*.json"] {   // last covers trace.json
            let s = BetterleaksSanitizer(scanner: scanner, exemptPaths: [pattern])
            await #expect(throws: SanitizerError.self, "exempting \(pattern) should fail closed") {
                _ = try await s.sanitize(bundle("token ghp_X", toolInput: "x"))
            }
        }
    }

    @Test("A secret hidden in a body-file KEY (filename) is scrubbed from the key, not just values")
    func scrubsSecretInBodyKey() async throws {
        let secret = "ghp_KEYLEAK"
        // The scanner reports the secret on the synthetic "paths" artifact (the body-keys blob).
        let scanner = StubScanner(findings: [Finding(ruleID: "github-pat", secret: secret, file: "paths")])
        var b = bundle("clean", toolInput: "clean")
        b.bodies = ["\(secret).txt": "clean body"]                     // the secret hides in the filename
        let (redacted, _) = try await BetterleaksSanitizer(scanner: scanner).sanitize(b)
        #expect(redacted.bodies["\(secret).txt"] == nil)              // raw key gone
        #expect(!redacted.bodies.keys.contains { $0.contains(secret) })
        #expect(redacted.bodies.keys.contains { $0.contains("[REDACTED:github-pat]") })
    }

    @Test("A finding on an exempt path is NOT redacted (silenced false positive)")
    func exemptPathKept() async throws {
        let scanner = StubScanner(findings: [
            Finding(ruleID: "aws", secret: "KEEP_ME", file: "fixtures/sample.md"),   // exempt
            Finding(ruleID: "gh", secret: "SCRUB_ME", file: "transcript.md"),        // not exempt
        ])
        let s = BetterleaksSanitizer(scanner: scanner, exemptPaths: ["fixtures/sample.md"])
        let (redacted, report) = try await s.sanitize(bundle("has KEEP_ME and SCRUB_ME", toolInput: "none"))

        #expect(redacted.transcript.contains("KEEP_ME"))          // exempt finding → left alone
        #expect(!redacted.transcript.contains("SCRUB_ME"))        // non-exempt → scrubbed
        #expect(report.redactions == 4)   // SCRUB_ME occurrences: transcript + diff + body value + trace text
    }

    @Test("redactions counts [REDACTED] markers (merged spans), not distinct secrets — grep-verifiable")
    func redactionsCountsMarkers() async throws {
        let scanner = StubScanner(findings: [Finding(ruleID: "gh", secret: "ghp_X", file: "transcript.md")])
        var b = bundle("", toolInput: "")           // clear trace text; SEPARATED occurrences → distinct markers
        b.transcript = "ghp_X ghp_X ghp_X"; b.diff = ""; b.bodies = [:]
        let (_, report) = try await BetterleaksSanitizer(scanner: scanner).sanitize(b)
        #expect(report.redactions == 3)             // 3 markers, not 1 distinct secret
        // ADJACENT repeats collapse into ONE contiguous marker → the count matches the grep count (1, not 3).
        b.transcript = "ghp_Xghp_Xghp_X"
        let (redacted2, report2) = try await BetterleaksSanitizer(scanner: scanner).sanitize(b)
        #expect(report2.redactions == 1)
        #expect(redacted2.transcript == "[REDACTED:gh]")
    }

    @Test("No findings (clean) → unchanged, redactions 0")
    func clean() async throws {
        let s = BetterleaksSanitizer(scanner: StubScanner(findings: []))
        let input = bundle("nothing secret", toolInput: "ls")
        let (redacted, report) = try await s.sanitize(input)
        #expect(redacted == input)
        #expect(report.redactions == 0)
        #expect(report.scanner == "betterleaks")
    }
}
