import Foundation

/// Wikipedia-derived word-lists for AI-writing detection (`WP:AIVOCAB` / `WP:AIPUFFERY` /
/// `WP:AIDASH`), ported verbatim (F17) from the predecessor's `SkillEvalKit/Scoring/Code/AIVocabulary`.
/// `combined` feeds the slop-vocabulary check (S001); `puffery` feeds the marketing-puffery check
/// (S002); `knowledgeCutoffPhrases` feeds the knowledge-cutoff check (S005). Kept in-code (small,
/// curated); large lists would move to a resource file (design §5.2), a deferred option.
public enum AIVocabulary {
    /// The broadest combined AI-vocabulary net (Wikipedia's inclusive-ascending GPT-4 era list).
    public static let combined: [String] = [
        // gpt5 era
        "emphasizing", "enhance", "highlighting", "showcasing",
        // gpt4o additions
        "align with", "bolstered", "crucial", "enduring", "fostering", "pivotal", "underscore", "vibrant",
        // gpt4 additions
        "additionally", "boasts", "delve", "garner", "intricate", "intricacies", "interplay",
        "landscape", "meticulous", "meticulously", "tapestry", "testament", "valuable",
    ]

    /// Promotional / puffery language (`WP:AIPUFFERY`).
    public static let puffery: [String] = [
        "vibrant", "rich tapestry", "stands as", "seamlessly",
        "world-class", "nestled", "breathtaking", "lifeline",
    ]

    /// Knowledge-cutoff disclaimers — an AI model hedging about training-data recency. **Substring**
    /// match (not word-boundary), because most are multi-word phrases.
    public static let knowledgeCutoffPhrases: [String] = [
        "as of my last", "knowledge cutoff", "i cannot verify", "my training data",
        "i do not have access", "i don't have access", "i'm not able to access", "last updated knowledge",
    ]
}

/// Text statistics — the density denominators, ported verbatim from the predecessor (F17). Denominators
/// count `Character`s (graphemes), matching the predecessor so calibration transfers; SARIF *regions*
/// count Unicode scalars separately (§4.3).
enum SlopTextStats {
    /// Approximate word count: whitespace-separated tokens containing at least one letter or digit (so
    /// em-dashes, lone punctuation, and decorative glyphs don't inflate the count).
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { token in token.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }

    /// Approximate sentence count: `.`/`!`/`?` followed by whitespace or end-of-string. Capped at min 1
    /// for non-empty text so per-100-sentences math doesn't divide by zero on prose without terminal
    /// punctuation.
    static func sentenceCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        let chars = Array(text)
        for i in 0..<chars.count {
            let c = chars[i]
            if c == "." || c == "!" || c == "?" {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if next.isWhitespace || next.isNewline { count += 1 }
            }
        }
        return max(1, count)
    }
}
