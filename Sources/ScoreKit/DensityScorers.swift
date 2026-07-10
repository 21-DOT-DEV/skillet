import Foundation
import EDDCore

// MARK: - Match helpers (each returns the located ranges, so a count becomes located findings)

/// Word-boundary, case-insensitive matches of any phrase — for the vocabulary checks (S001/S002).
func wordBoundaryMatches(phrases: [String], in text: String) -> [Range<String.Index>] {
    var out: [Range<String.Index>] = []
    let full = NSRange(text.startIndex..., in: text)
    for phrase in phrases {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: phrase) + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
        for m in regex.matches(in: text, range: full) where Range(m.range, in: text) != nil {
            out.append(Range(m.range, in: text)!)
        }
    }
    return out
}

/// Case-insensitive **substring** matches on the original text (not a lowercased copy, so scalar offsets
/// stay accurate) — for the knowledge-cutoff phrases (S005), which are multi-word and not word-bounded.
func substringMatches(phrases: [String], in text: String) -> [Range<String.Index>] {
    var out: [Range<String.Index>] = []
    for phrase in phrases where !phrase.isEmpty {
        var start = text.startIndex
        while let r = text.range(of: phrase, options: [.caseInsensitive], range: start..<text.endIndex) {
            out.append(r)
            start = r.upperBound   // non-overlapping
        }
    }
    return out
}

/// Every U+2014 em-dash scalar (not en-dash, not `--`) — for the em-dash check (S003).
func emDashMatches(in text: String) -> [Range<String.Index>] {
    var out: [Range<String.Index>] = []
    var i = text.startIndex
    while i < text.endIndex {
        let next = text.index(after: i)
        if text[i] == "\u{2014}" { out.append(i..<next) }
        i = next
    }
    return out
}

/// The three "not X, but Y" contrast families (S006) — regex-only, each within one sentence.
func contrastMatches(in text: String) -> [Range<String.Index>] {
    let patterns = [
        #"\bnot\s+(just|only|merely|simply)\b[^.?!\n]{0,60}?\bbut\b"#,
        #"\b(it|that|this|they|we|you)['’]?s\b[^.?!\n]{0,60}?,\s*(it['’]?s|but)\b"#,
        #"\bless\s+about\b[^.?!\n]{0,60}?\bmore\s+about\b"#,
    ]
    var out: [Range<String.Index>] = []
    let full = NSRange(text.startIndex..., in: text)
    for p in patterns {
        guard let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
        for m in regex.matches(in: text, range: full) where Range(m.range, in: text) != nil {
            out.append(Range(m.range, in: text)!)
        }
    }
    return out
}

/// Rule-of-three matcher with a referential/technical skip, ported + generalized (S004). A `X, Y, and Z`
/// triple is NOT counted when ≥2 items are referential (markdown link or inline code) or technical
/// (all-caps run, digit-bearing, or identifier punctuation) — so concrete technical enumerations
/// ("P2WPKH, P2WSH, and P2SH") don't over-flag. Returns the whole-triple ranges.
enum RuleOfThreeMatcher {
    static func rhetoricalTripleRanges(in text: String) -> [Range<String.Index>] {
        let pattern = #"([^,.;!?\n]{1,60}),\s+([^,.;!?\n]{1,60}),\s+(?:and\s+)?([^,.;!?\n]{1,60})(?:[.,;!?\s]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        var out: [Range<String.Index>] = []
        for m in regex.matches(in: text, range: full) where m.numberOfRanges == 4 {
            guard let r0 = Range(m.range(at: 0), in: text),
                  let r1 = Range(m.range(at: 1), in: text),
                  let r2 = Range(m.range(at: 2), in: text),
                  let r3 = Range(m.range(at: 3), in: text) else { continue }
            let items = [r1, r2, r3].map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
            let concrete = items.filter { isReferential($0) || isTechnical($0) }.count
            if concrete < 2 { out.append(r0) }
        }
        return out
    }

    static func isReferential(_ item: String) -> Bool {
        if item.contains("](") { return true }                                            // markdown link
        if item.range(of: #"`[^`]+`"#, options: .regularExpression) != nil { return true }  // inline code (generalizes DocC ``X``)
        return false
    }

    static func isTechnical(_ item: String) -> Bool {
        if item.range(of: #"[A-Z]{2,}"#, options: .regularExpression) != nil { return true }   // all-caps acronym
        if item.range(of: #"\d"#, options: .regularExpression) != nil { return true }          // digit-bearing
        if item.contains("_") || item.contains("::") || item.contains("/") { return true }     // identifier / path
        return false
    }
}

// MARK: - The six density scorers (S001–S006)

struct SlopVocabularyScorer: Scorer {
    let ruleId = "SKILL-S001"; let name = "slop-vocabulary"
    let scale = ScorerScale(min: 0, max: 20, good: .low)
    func measure(_ file: ScoredFile, config: SkilletConfig.Scorers) -> ScorerMeasurement {
        let words = SlopTextStats.wordCount(file.text)
        guard words > 0 else { return .notApplicable }
        let exempt = Set(config.vocab.exempt.map { $0.lowercased() })
        let phrases = AIVocabulary.combined.filter { !exempt.contains($0.lowercased()) }
        let occ = wordBoundaryMatches(phrases: phrases, in: file.text).map {
            Occurrence(range: $0, message: "AI-slop vocabulary: `\(file.text[$0])`")
        }
        return .density(value: Double(occ.count) / Double(words) * 1000, denominator: words, occurrences: occ)
    }
}

struct PufferyScorer: Scorer {
    let ruleId = "SKILL-S002"; let name = "puffery"
    let scale = ScorerScale(min: 0, max: 20, good: .low)
    func measure(_ file: ScoredFile, config: SkilletConfig.Scorers) -> ScorerMeasurement {
        let words = SlopTextStats.wordCount(file.text)
        guard words > 0 else { return .notApplicable }
        let exempt = Set(config.vocab.exempt.map { $0.lowercased() })
        let phrases = AIVocabulary.puffery.filter { !exempt.contains($0.lowercased()) }
        let occ = wordBoundaryMatches(phrases: phrases, in: file.text).map {
            Occurrence(range: $0, message: "Marketing puffery: `\(file.text[$0])`")
        }
        return .density(value: Double(occ.count) / Double(words) * 1000, denominator: words, occurrences: occ)
    }
}

struct EmDashScorer: Scorer {
    let ruleId = "SKILL-S003"; let name = "em-dash"
    let scale = ScorerScale(min: 0, max: 10, good: .target(1.5))
    func measure(_ file: ScoredFile, config: SkilletConfig.Scorers) -> ScorerMeasurement {
        let words = SlopTextStats.wordCount(file.text)
        guard words > 0 else { return .notApplicable }
        let occ = emDashMatches(in: file.text).map { Occurrence(range: $0, message: "Over-used em-dash") }
        return .density(value: Double(occ.count) / Double(words) * 100, denominator: words, occurrences: occ)
    }
}

struct RuleOfThreeScorer: Scorer {
    let ruleId = "SKILL-S004"; let name = "rule-of-three"
    let scale = ScorerScale(min: 0, max: 20, good: .low)
    func measure(_ file: ScoredFile, config: SkilletConfig.Scorers) -> ScorerMeasurement {
        let sentences = SlopTextStats.sentenceCount(file.text)
        guard sentences > 0 else { return .notApplicable }
        let occ = RuleOfThreeMatcher.rhetoricalTripleRanges(in: file.text).map {
            Occurrence(range: $0, message: "Rule-of-three rhetorical triple")
        }
        return .density(value: Double(occ.count) / Double(sentences) * 100, denominator: sentences, occurrences: occ)
    }
}

struct KnowledgeCutoffScorer: Scorer {
    let ruleId = "SKILL-S005"; let name = "knowledge-cutoff"
    let scale = ScorerScale(min: 0, max: 5, good: .low)
    func measure(_ file: ScoredFile, config: SkilletConfig.Scorers) -> ScorerMeasurement {
        guard !file.text.isEmpty else { return .notApplicable }
        let occ = substringMatches(phrases: AIVocabulary.knowledgeCutoffPhrases, in: file.text).map {
            Occurrence(range: $0, message: "Knowledge-cutoff disclaimer: `\(file.text[$0])`")
        }
        return .density(value: Double(occ.count), denominator: nil, occurrences: occ)   // raw count
    }
}

/// Experimental (default-off; §4.7). Regex-only approximation of EQ-Bench's contrast detector.
struct NotXButYScorer: Scorer {
    let ruleId = "SKILL-S006"; let name = "not-x-but-y"
    let scale = ScorerScale(min: 0, max: 15, good: .low)   // provisional; pinned by the calibration fixture
    func measure(_ file: ScoredFile, config: SkilletConfig.Scorers) -> ScorerMeasurement {
        let words = SlopTextStats.wordCount(file.text)
        guard words > 0 else { return .notApplicable }
        let occ = contrastMatches(in: file.text).map {
            Occurrence(range: $0, message: "\"not X, but Y\" contrast construction")
        }
        return .density(value: Double(occ.count) / Double(words) * 1000, denominator: words, occurrences: occ)
    }
}
