import Foundation

/// The outcome of scanning a document for its leading `---…---` frontmatter block. Shared by
/// ``FrontmatterParser`` (a `SKILL.md`) and ``EvidenceFrontmatter`` (an evidence file) so the
/// CRLF-normalized delimiter scan lives in **one place** — each caller maps these cases to its own typed
/// error vocabulary (`FrontmatterError` vs. `ConfigError`), empty-block policy, and body post-processing.
enum FrontmatterSplit {
    /// The document doesn't open with a `---` delimiter.
    case noOpening
    /// An opening `---` with no closing `---`.
    case unterminated
    /// Delimited: the raw YAML text and the raw body after the closing `---`. `yaml` may be
    /// whitespace-only — the caller decides whether an empty block is valid.
    case split(yaml: String, body: String)

    /// Scan `text` for the leading block. **Never throws** — the delimiter grammar is caller-neutral, so
    /// each caller owns the error type. CRLF is normalized first so scalars/body never carry a stray `\r`
    /// (files are conventionally LF, but a Windows checkout can be CRLF).
    static func scan(_ text: String) -> FrontmatterSplit {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func isDelimiter(_ index: Int) -> Bool {
            lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }
        guard let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return .noOpening
        }
        guard let close = lines.indices.dropFirst().first(where: isDelimiter) else { return .unterminated }
        let yaml = lines[1..<close].joined(separator: "\n")
        let body = close + 1 < lines.count ? lines[(close + 1)...].joined(separator: "\n") : ""
        return .split(yaml: yaml, body: body)
    }
}
