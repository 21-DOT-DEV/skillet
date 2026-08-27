import Foundation

/// The name a test is known by — **the key every comparison joins on**: which "before" row pairs with
/// which "after" row, which with-skill row pairs with which without-skill row, and which of last week's
/// results carries forward to this week's for the same test.
///
/// **Why a test with no name is not simply numbered.** A name is optional, and most real skills give
/// none — three of four in the corpus this tool was adapted from name no test at all. Numbering them by
/// position made the key move whenever the file was edited: insert a test near the top and every test
/// below it silently inherits the history of its neighbour, with nothing printed and nothing left over
/// to notice. An identity invented from a position is an identity nobody chose and nobody can keep.
///
/// So an unnamed test is named from **its own content** instead. That survives reordering and insertion,
/// reads as something recognisable in a report, and changes only when the test itself is rewritten —
/// which is a defensible moment for its history to start again, and avoidable by writing a name.
public enum EvalName {
    /// How many characters of the prompt are used before the distinguishing suffix.
    public static let readableLimit = 28

    /// The name to use for a test, given what it says and where it sits.
    ///
    /// `position` is used only when there is nothing else at all — a test with neither a name nor a
    /// prompt, which every paid command refuses before spending, so it exists here only to keep this
    /// total rather than to be relied upon.
    public static func resolve(id: String?, prompt: String?, position: Int) -> String {
        if let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return id }
        guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "unnamed-\(position)"
        }
        let readable = slug(prompt)
        // **Wide enough that two distinct tests do not collide.** Four hex characters gave 65,536
        // possible endings, and the readable part is cut to a fixed length — so a suite whose prompts
        // share an opening phrase leaves the ending as the only thing telling them apart. Measured at
        // that width: 200 tests with a realistic shared stem produced 8 pairs that collided, and each
        // would have been refused as a duplicate despite being genuinely different. Eight characters
        // removes it: the same measurement produces none.
        let suffix = String(format: "%08x", UInt32(truncatingIfNeeded: stableHash(prompt)))
        return readable.isEmpty ? "unnamed-\(suffix)" : "\(readable)-\(suffix)"
    }

    /// Lower-case words joined by hyphens, cut to a readable length on a word boundary.
    /// Exposed for the language-independence check, which has to compare the readable part alone —
    /// comparing whole names across two spellings would compare hashes of two different texts.
    public static func slugForTesting(_ text: String) -> String { slug(text) }

    static func slug(_ text: String) -> String {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        var out = ""
        for word in words {
            // **The joining hyphen is only charged when one is actually written.** Charging it for the
            // first word too made the limit mean two different things: a name built from several words
            // could reach the full length, while a single opening word was cut one short — so a prompt
            // that is one word of exactly the limit was dropped entirely and the test was named
            // `unnamed-<hash>`, unreadable, while the same prompt one letter shorter kept its name.
            let separator = out.isEmpty ? 0 : 1
            if out.count + word.count + separator > readableLimit { break }
            out += out.isEmpty ? String(word) : "-\(word)"
        }
        return out
    }

    /// **Deterministic across runs and machines**, which the language's built-in hashing is deliberately
    /// not — it is seeded afresh per process, so a name built from it would differ between two runs of
    /// the same command and every stored result would stop lining up. FNV-1a, chosen for being short,
    /// stable, and standard; nothing here needs it to resist an adversary.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
