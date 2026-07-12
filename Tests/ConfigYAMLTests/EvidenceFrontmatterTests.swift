import Testing
import Foundation
import EDDCore
@testable import ConfigYAML

@Suite("EvidenceFrontmatter — decode/validate + create-encode (F29 seam)")
struct EvidenceFrontmatterTests {
    let friction = """
    ---
    schema: skillet.friction/1
    id: 2026-06-07-snippets-dont-compile
    skill: docc-articles
    domain: secp256k1
    lever: eval
    state: held
    state_reason: single-domain; only strong lever is compile-eval infra
    root_cause: "SKILL.md:214 — snippets must compile"
    sessions: [2026-06-01-secp-sign, 2026-06-04-secp-verify]
    skill_version: "1.3.0"
    model: claude-opus-4-8
    ---
    Invocation: asked for a signing walkthrough article for P256K…
    """

    @Test func decodesAValidFriction() throws {
        let (ev, body) = try EvidenceFrontmatter.decode(friction, filename: "2026-06-07-snippets-dont-compile.md")
        let f = try #require(ev as? FrictionEvent)
        #expect(f.header.skill == "docc-articles")
        #expect(f.header.domain == "secp256k1")
        #expect(f.header.lever == .eval)
        #expect(f.header.state == .held)
        #expect(f.header.stateReason?.contains("single-domain") == true)   // snake_case state_reason → stateReason
        #expect(f.header.sessions.count == 2)
        #expect(f.header.skillVersion == "1.3.0")
        #expect(body.contains("Invocation:"))
    }

    @Test func decodesAValidFinding() throws {
        let yaml = """
        ---
        schema: skillet.finding/1
        id: 2026-06-05-rule-of-three-density
        skill: docc-articles
        domain: secp256k1
        lever: skill_md
        state: logged
        source: scorer
        confidence: high
        cluster: rule-of-three
        signal: density-below-threshold
        ---
        body text
        """
        let (ev, _) = try EvidenceFrontmatter.decode(yaml)
        let f = try #require(ev as? Finding)
        #expect(f.source == .scorer)
        #expect(f.confidence == .high)
        #expect(f.header.lever == .skillMd)          // skill_md value → .skillMd
        #expect(f.cluster == "rule-of-three")
    }

    @Test func createEncodeRoundTrips() throws {
        let original = FrictionEvent(header: EvidenceHeader(
            id: "2026-06-07-a-note", skill: "s", domain: "d", lever: .eval, state: .logged, sessions: ["a"]))
        let text = try EvidenceFrontmatter.encode(original, body: "the note body")
        #expect(text.hasPrefix("---\n"))
        #expect(text.contains("skillet.friction/1"))
        #expect(text.contains("skill_version"))       // snake_case emitted
        #expect(text.hasSuffix("the note body\n"))     // POSIX-terminated file (the `\n` is not body content)
        let (back, body) = try EvidenceFrontmatter.decode(text)
        #expect(try #require(back as? FrictionEvent) == original)   // decode(encode(x)) == x
        #expect(body == "the note body")               // …and the terminator newline is stripped back off
    }

    @Test func createEncodeRoundTripsFinding() throws {
        // The finding-only fields (source/confidence + the optional cluster/signal) get their own YAML
        // create-encode path; a key-order / optional / snake_case emission bug here is invisible to the
        // FrictionEvent round-trip and to the JSON-only coverage in EvidenceTests.
        let original = Finding(
            header: EvidenceHeader(
                id: "2026-06-05-density", skill: "s", domain: "d", lever: .skillMd, state: .logged, sessions: ["x"]),
            source: .judge, confidence: .medium, cluster: "rule-of-three", signal: "density-below-threshold")
        let text = try EvidenceFrontmatter.encode(original, body: "finding body")
        #expect(text.contains("skillet.finding/1"))
        #expect(text.contains("confidence:"))          // finding-only field emitted at the top level
        #expect(text.hasSuffix("finding body\n"))
        let (back, body) = try EvidenceFrontmatter.decode(text)
        let f = try #require(back as? Finding)
        #expect(f == original)                         // decode(encode(x)) == x — incl. optional cluster/signal
        #expect(f.header.lever == .skillMd)            // camelCase lever value ↔ snake_case `skill_md` survives
        #expect(body == "finding body")
    }

    @Test func rejectsADuplicateKeyNatively() {
        let dup = """
        ---
        schema: skillet.friction/1
        id: 2026-06-07-x
        skill: s
        domain: d
        lever: eval
        state: logged
        state: closed
        ---
        body
        """
        #expect(throws: ConfigError.self) { _ = try EvidenceFrontmatter.decode(dup) }   // doubled `state:`
    }

    @Test func rejectsMissingAndUnknownSchema() {
        #expect(throws: EvidenceError.self) {
            _ = try EvidenceFrontmatter.decode("---\nid: 2026-06-07-x\nskill: s\n---\nb")            // no schema
        }
        #expect(throws: EvidenceError.unknownSchema("skillet.bogus/1")) {
            _ = try EvidenceFrontmatter.decode("---\nschema: skillet.bogus/1\nid: 2026-06-07-x\n---\nb")
        }
    }

    @Test func rejectsBadEnumAndMissingRequiredField() {
        #expect(throws: EvidenceError.self) {   // state: codfied → invalidValue
            _ = try EvidenceFrontmatter.decode("---\nschema: skillet.friction/1\nid: 2026-06-07-x\nskill: s\ndomain: d\nlever: eval\nstate: codfied\n---\nb")
        }
        #expect(throws: EvidenceError.self) {   // no `domain` → missingField
            _ = try EvidenceFrontmatter.decode("---\nschema: skillet.friction/1\nid: 2026-06-07-x\nskill: s\nlever: eval\nstate: logged\n---\nb")
        }
    }

    @Test func heldWithoutReasonAndFilenameMismatchFailValidation() {
        #expect(throws: EvidenceError.self) {   // held sans state_reason → missingStateReason
            _ = try EvidenceFrontmatter.decode("---\nschema: skillet.friction/1\nid: 2026-06-07-x\nskill: s\ndomain: d\nlever: eval\nstate: held\n---\nb")
        }
        #expect(throws: EvidenceError.self) {   // id ≠ filename stem → idMismatch
            _ = try EvidenceFrontmatter.decode(friction, filename: "wrong-name.md")
        }
    }

    @Test func structuralFailuresStayConfigErrorsNotFieldErrors() {
        // The whole frontmatter isn't a mapping (a bare scalar) → structural → ConfigError (the seam owns
        // YAML shape, D4), NOT a pure-core EvidenceError.invalidValue(field: "?").
        #expect(throws: ConfigError.self) { _ = try EvidenceFrontmatter.decode("---\njust a bare scalar\n---\nbody") }
        // Invalid YAML syntax (an unterminated flow sequence) → wrapped `YAMLError.parse` → ConfigError.
        #expect(throws: ConfigError.self) { _ = try EvidenceFrontmatter.decode("---\nfoo: [unterminated\n---\nbody") }
    }

    @Test func encodedFrictionKeyOrderMatchesTheDesignExample() throws {
        // The emitted field order is load-bearing: it must match the skillet-design.md §7.3 friction
        // example (plan §5 — create-encode's "declaration order matches the example", no regeneration).
        // A fully-populated record exercises every header field and proves the encoder preserves
        // insertion order (no sorting) + snake_case conversion.
        let ev = FrictionEvent(header: EvidenceHeader(
            id: "2026-06-07-x", skill: "s", domain: "d", lever: .eval, state: .held,
            stateReason: "r", rootCause: "rc", sessions: ["a"],
            skillVersion: "1.3.0", model: "m", eval: "evals.json#x"))
        let text = try EvidenceFrontmatter.encode(ev, body: "b")
        #expect(frontmatterKeys(text) == ["schema", "id", "skill", "domain", "lever", "state",
                                          "state_reason", "root_cause", "sessions", "skill_version", "model", "eval"])
    }

    @Test func malformedSessionsElementNamesTheSessionsField() {
        // A non-string `sessions` element (a nested sequence) throws at codingPath ["sessions", 0]; the
        // reported field must keep the `sessions` context (e.g. `sessions[0]`), never the bare index `0`.
        let bad = "---\nschema: skillet.friction/1\nid: 2026-06-07-x\nskill: s\ndomain: d\nlever: eval\nstate: logged\nsessions: [[nested, seq]]\n---\nb"
        do {
            _ = try EvidenceFrontmatter.decode(bad)
            Issue.record("expected a decode error for a non-string sessions element")
        } catch let EvidenceError.invalidValue(field, _) {
            #expect(field.contains("sessions"))   // "sessions[0]", never "0"
        } catch {
            Issue.record("expected EvidenceError.invalidValue naming sessions, got \(error)")
        }
    }

    /// Top-level frontmatter keys in emitted order (for the order-golden): the `---`-delimited head, the
    /// key before the first `:` on each unindented line (block-list items indent, so they're skipped).
    private func frontmatterKeys(_ text: String) -> [String] {
        var keys: [String] = []
        var inBlock = false
        for line in text.components(separatedBy: "\n") {
            if line == "---" { if inBlock { break }; inBlock = true; continue }
            guard inBlock, let first = line.first, !first.isWhitespace,
                  let colon = line.firstIndex(of: ":") else { continue }
            keys.append(String(line[line.startIndex..<colon]))
        }
        return keys
    }
}
