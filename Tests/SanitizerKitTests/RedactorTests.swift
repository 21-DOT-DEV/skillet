import Testing
@testable import SanitizerKit

@Suite("Redactor — span-merge value-based redaction")
struct RedactorTests {
    typealias S = Redactor.Secret

    @Test("Replaces every occurrence with a typed marker")
    func everyOccurrence() {
        let r = Redactor.redact("key AKIA1 and again AKIA1 end", secrets: [S(value: "AKIA1", rule: "aws")])
        #expect(r.text == "key [REDACTED:aws] and again [REDACTED:aws] end")
        #expect(r.redactions == 2)
    }

    // Containment: "abcd" contains "abc". A naïve sequential replace could turn "abcd" into
    // "[REDACTED]d" (leaking the 'd'). Span-merge resolves spans first, so no fragment survives — in
    // either input order (deterministic).
    @Test("Containment leaves no fragment, order-independent")
    func containment() {
        let text = "x abcd y"
        let a = Redactor.redact(text, secrets: [S(value: "abc", rule: "r1"), S(value: "abcd", rule: "r2")])
        let b = Redactor.redact(text, secrets: [S(value: "abcd", rule: "r2"), S(value: "abc", rule: "r1")])
        #expect(a.text == b.text)
        #expect(a.text == "x [REDACTED:multiple] y")
        #expect(!a.text.contains("d y"))
    }

    @Test("Adjacent secrets merge into one marker")
    func adjacent() {
        let r = Redactor.redact("abcdef", secrets: [S(value: "abc", rule: "r1"), S(value: "def", rule: "r2")])
        #expect(r.text == "[REDACTED:multiple]")
        #expect(r.redactions == 1)
    }

    @Test("A single secret repeated back-to-back is ONE contiguous marker → redactions == 1 (grep-verifiable)")
    func adjacentSameSecret() {
        // The reviewer's exact shape: "abcabcabc" with secret "abc" is one run, not three markers.
        let r = Redactor.redact("abcabcabc", secrets: [S(value: "abc", rule: "r1")])
        #expect(r.text == "[REDACTED:r1]")
        #expect(r.redactions == 1)
    }

    @Test("Non-adjacent occurrences stay separate, labeled by their own rule")
    func separate() {
        let r = Redactor.redact("abc gap def", secrets: [S(value: "abc", rule: "r1"), S(value: "def", rule: "r2")])
        #expect(r.text == "[REDACTED:r1] gap [REDACTED:r2]")
        #expect(r.redactions == 2)
    }

    @Test("Empty secret value is ignored (would otherwise match everywhere)")
    func emptyIgnored() {
        let r = Redactor.redact("hello", secrets: [S(value: "", rule: "x")])
        #expect(r.text == "hello")
        #expect(r.redactions == 0)
    }

    @Test("No secrets / empty text → unchanged")
    func noop() {
        #expect(Redactor.redact("hello", secrets: []).text == "hello")
        #expect(Redactor.redact("", secrets: [S(value: "x", rule: "r")]).text == "")
    }
}
