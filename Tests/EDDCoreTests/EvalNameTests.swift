import Foundation
import Testing
import EDDCore

/// The name a test is known by is the key every comparison joins on, so it must not move when the file
/// around it is edited — and it must be the same on two machines and in two runs.
@Suite("EvalName — a key that does not move")
struct EvalNameTests {
    private let prompt = "Tidy these notes into action items: Ana drafts the plan by Friday."

    @Test("A written name is used exactly as written")
    func writtenNameWins() throws {
        #expect(EvalName.resolve(id: "names-owners", prompt: prompt, position: 3) == "names-owners")
    }

    @Test("A blank written name is treated as none")
    func blankNameIsNoName() throws {
        #expect(EvalName.resolve(id: "   ", prompt: prompt, position: 0)
                    == EvalName.resolve(id: nil, prompt: prompt, position: 0))
    }

    /// The defect this replaces: a name taken from position moved whenever a test was inserted above,
    /// handing one test's accumulated history to another with nothing printed.
    @Test("An unnamed test keeps its name when the file is reordered")
    func nameSurvivesReordering() throws {
        let atTop = EvalName.resolve(id: nil, prompt: prompt, position: 0)
        let moved = EvalName.resolve(id: nil, prompt: prompt, position: 7)
        #expect(atTop == moved, "position must not be part of the name")
    }

    @Test("Two different tests get two different names")
    func differentContentDiffers() throws {
        #expect(EvalName.resolve(id: nil, prompt: prompt, position: 0)
                    != EvalName.resolve(id: nil, prompt: "Summarise this incident report.", position: 0))
    }

    @Test("The name is readable, not an opaque string")
    func nameIsReadable() throws {
        let name = EvalName.resolve(id: nil, prompt: prompt, position: 0)
        #expect(name.hasPrefix("tidy-these-notes"), "got \(name)")
        #expect(name.count <= EvalName.readableLimit + 12, "readable part plus a distinguishing ending")
    }

    /// The language's built-in hashing is seeded afresh per process on purpose, so a name built from it
    /// would differ between two runs of the same command and every stored result would stop lining up.
    @Test("The same text always gives the same name")
    func nameIsStable() throws {
        let expected = EvalName.resolve(id: nil, prompt: prompt, position: 0)
        for _ in 0..<50 { #expect(EvalName.resolve(id: nil, prompt: prompt, position: 0) == expected) }
    }

    @Test("A test with nothing to go on still gets a name rather than crashing")
    func emptyIsTotal() throws {
        #expect(!EvalName.resolve(id: nil, prompt: nil, position: 2).isEmpty)
        #expect(!EvalName.resolve(id: nil, prompt: "   ", position: 2).isEmpty)
    }
}

/// The name of a test must be the same on every machine, whatever the operating system's language is
/// set to. Reviewed as a possible fault on the grounds that lowercasing is language-sensitive: it is,
/// but only through the method that takes a language explicitly. The one used here does not, and this
/// pins that — if it were ever swapped for the language-aware one, a Turkish machine would name the same
/// test differently and every stored result would stop lining up.
@Suite("EvalName — the same name on every machine")
struct EvalNameLocaleTests {
    /// A capital `I` becomes a dotless `ı` under Turkish rules and a plain `i` everywhere else, so it is
    /// the case that would betray a language-aware lowercasing. Asserted on the readable part of the
    /// name — comparing whole names across two spellings would compare hashes of two different texts,
    /// which is a different question.
    @Test("A capital I lowercases the same way regardless of the machine's language",
          arguments: [("INCIDENT report", "incident"), ("Işık raporu", "i"), ("ÍNDICE", "índice")])
    func lowercasingIsLanguageIndependent(text: String, expected: String) {
        let name = EvalName.resolve(id: nil, prompt: text, position: 0)
        #expect(name.hasPrefix(expected), "got \(name), expected it to start with \(expected)")
        #expect(!name.hasPrefix("ı"), "a dotless ı means language-aware lowercasing crept in: \(name)")
        // **Compared against a language-neutral lowercasing, not against a second copy of the rule.**
        // This used to rebuild the whole naming rule here — splitting, joining and length-limiting — and
        // check the real one matched. That proves only that two copies of one rule agree, so a fault in
        // the rule appears in both and the test stays green: it did exactly that, passing while a prompt
        // of one word at the length limit was being dropped and named `unnamed-<hash>`. Only the part
        // this test is actually about is checked here.
        #expect(EvalName.slugForTesting(text).hasPrefix(expected),
                "the readable part must match what a language-neutral lowercasing produces")
        #expect(EvalName.slugForTesting(text) == EvalName.slugForTesting(text.lowercased(with: Locale(identifier: ""))),
                "lowercasing first, with no language, must change nothing — if it does, one of the two is language-aware")
    }
}

/// The readable part of a name is cut to a fixed length, so a suite whose prompts share an opening
/// phrase leaves only the ending to tell them apart. At four hex characters that ending had 65,536
/// possibilities, and genuinely different tests collided — each then refused as a duplicate.
@Suite("EvalName — distinct tests get distinct names at scale")
struct EvalNameCollisionTests {
    private func names(_ count: Int, _ make: (Int) -> String) -> Set<String> {
        Set((0..<count).map { EvalName.resolve(id: nil, prompt: make($0), position: $0) })
    }

    @Test("Two hundred tests sharing an opening phrase all get different names")
    func sharedStemStaysDistinct() {
        let made = names(200) { "Tidy these notes into action items, variant \($0)" }
        #expect(made.count == 200, "\(200 - made.count) pairs collided")
    }

    @Test("Two hundred varied tests all get different names")
    func variedStayDistinct() {
        let made = names(200) { "Check that the report handles case \($0) correctly" }
        #expect(made.count == 200, "\(200 - made.count) pairs collided")
    }

    @Test("A thousand tests still get a thousand names")
    func holdsAtLargerScale() {
        let made = names(1_000) { "Verify behaviour number \($0) end to end" }
        #expect(made.count == 1_000, "\(1_000 - made.count) pairs collided")
    }
}

/// **How long a readable name may be, and the one length that used to fall through the gap.**
///
/// A test with no name of its own gets one built from its instruction: the opening words, lower-cased and
/// joined by hyphens, cut on a word boundary, followed by a short fingerprint of the full text so two
/// tests that start alike stay distinguishable. When nothing readable survives the cut, the name is just
/// `unnamed-` and the fingerprint — correct, but useless to read in a table of results.
///
/// The cut used to charge for a joining hyphen even before there was anything to join to, so the limit
/// meant two different things: a name assembled from several words could reach the full length, while a
/// single opening word was cut one character short. A prompt that was one word of exactly the limit was
/// therefore thrown away whole, while the same prompt one letter shorter kept its name.
@Suite("A readable name is cut at the stated length, not one short of it")
struct EvalNameLengthTests {
    private func word(_ count: Int) -> String { String(repeating: "a", count: count) }

    @Test("A single word of exactly the limit is kept whole")
    func singleWordAtTheLimitIsKept() {
        let text = word(EvalName.readableLimit)
        #expect(EvalName.slugForTesting(text) == text)
        #expect(!EvalName.resolve(id: nil, prompt: text, position: 0).hasPrefix("unnamed-"),
                "it fits, so the name must be readable rather than a bare fingerprint")
    }

    @Test("A single word one over the limit is dropped, leaving a fingerprint")
    func singleWordOverTheLimitIsDropped() {
        let text = word(EvalName.readableLimit + 1)
        #expect(EvalName.slugForTesting(text).isEmpty, "no word boundary to cut on, so nothing readable survives")
        #expect(EvalName.resolve(id: nil, prompt: text, position: 0).hasPrefix("unnamed-"))
    }

    /// The rule is the same however many words make up the length — which is the inconsistency that was
    /// there before: several words could reach the limit, one word could not.
    @Test("Several words reaching exactly the limit are all kept")
    func severalWordsAtTheLimit() {
        // 14 + hyphen + 13 = exactly the limit at its default of 28.
        let text = "\(word(14)) \(word(EvalName.readableLimit - 15))"
        let slug = EvalName.slugForTesting(text)
        #expect(slug.count == EvalName.readableLimit)
        #expect(slug.contains("-"))
    }

    @Test("A word that would take it past the limit is left off, and the earlier words stay")
    func laterWordOverTheLimitIsLeftOff() {
        let slug = EvalName.slugForTesting("\(word(20)) \(word(20))")
        #expect(slug == word(20), "the first fits, the second cannot, and nothing is cut mid-word")
    }

    /// Whatever the limit is set to, no readable part may exceed it — stated as a property so the
    /// numbers above cannot drift away from the rule they illustrate.
    @Test("No readable part ever exceeds the limit", arguments: 1...40)
    func neverExceedsTheLimit(length: Int) {
        #expect(EvalName.slugForTesting(word(length)).count <= EvalName.readableLimit)
        #expect(EvalName.slugForTesting("\(word(length)) \(word(length))").count <= EvalName.readableLimit)
    }
}
