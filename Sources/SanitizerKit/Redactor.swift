/// Value-based, span-merge redaction — the Microsoft-Presidio "resolve-then-redact" pattern.
///
/// Given a text and the set of detected `(secret value, rule)` pairs, it finds **every** occurrence of
/// **every** secret, merges overlapping *and* adjacent spans into maximal non-overlapping spans, then
/// replaces each merged span once with `[REDACTED:<rule>]` (a span covering more than one rule →
/// `[REDACTED:multiple]`). This is order-independent, deterministic, and provably fragment-free — a
/// shorter secret that is a substring of a longer one can never leave a dangling tail, because the merge
/// resolves spans *before* any replacement.
public enum Redactor {
    public struct Secret: Sendable, Equatable, Hashable {
        public let value: String
        public let rule: String
        public init(value: String, rule: String) { self.value = value; self.rule = rule }
    }

    public struct Result: Sendable, Equatable {
        public let text: String
        /// Count of `[REDACTED]` markers written = maximal **merged** spans. Adjacent/overlapping
        /// occurrences collapse into ONE marker (`abcabcabc` → 1); separated ones count separately
        /// (`abc abc abc` → 3). So it equals the markers a reader can grep in the output — deliberately
        /// NOT the raw occurrence count (a contiguous secret run is one redaction, one marker).
        public let redactions: Int
    }

    public static func redact(_ text: String, secrets: [Secret]) -> Result {
        // An empty value would match at every position — drop it. Dedupe identical (value,rule) pairs.
        let cleaned = Array(Set(secrets.filter { !$0.value.isEmpty }))
        guard !cleaned.isEmpty, !text.isEmpty else { return Result(text: text, redactions: 0) }

        // 1. Collect every occurrence span of every secret (non-overlapping *per secret*; cross-secret
        //    overlaps are resolved by the merge below).
        var spans: [(range: Range<String.Index>, rule: String)] = []
        for s in cleaned {
            var from = text.startIndex
            while let r = text.range(of: s.value, range: from..<text.endIndex) {
                spans.append((r, s.rule))
                from = r.upperBound
            }
        }
        guard !spans.isEmpty else { return Result(text: text, redactions: 0) }

        // 2. Sort by start, then merge overlapping/adjacent spans into maximal spans (collecting rules).
        spans.sort { $0.range.lowerBound < $1.range.lowerBound }
        var merged: [(range: Range<String.Index>, rules: Set<String>)] = []
        for span in spans {
            if let last = merged.last, span.range.lowerBound <= last.range.upperBound {
                let upper = Swift.max(last.range.upperBound, span.range.upperBound)
                var rules = last.rules
                rules.insert(span.rule)
                merged[merged.count - 1] = (last.range.lowerBound..<upper, rules)
            } else {
                merged.append((span.range, [span.rule]))
            }
        }

        // 3. Rebuild left-to-right (merged is ascending + non-overlapping). We only ever index into the
        //    ORIGINAL `text` (never a mutated copy), so String.Index stays valid.
        var out = ""
        var cursor = text.startIndex
        for m in merged {
            out += text[cursor..<m.range.lowerBound]
            let label = m.rules.count == 1 ? m.rules.first! : "multiple"
            out += "[REDACTED:\(label)]"
            cursor = m.range.upperBound
        }
        out += text[cursor..<text.endIndex]
        return Result(text: out, redactions: merged.count)
    }
}
