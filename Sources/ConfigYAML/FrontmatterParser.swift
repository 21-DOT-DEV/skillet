import Foundation
import YAML
import EDDCore

/// Why a `SKILL.md` frontmatter block couldn't be parsed. Malformed input is **data, not a crash**:
/// the linter maps any of these to an error-tier `SKILL-L001` diagnostic and keeps going (design
/// §6.1). Full key-level conformance (duplicate keys, allowed-keys) is F3 `doctor`.
public enum FrontmatterError: Error, Equatable {
    /// No leading `---` block — the file doesn't open with frontmatter.
    case missing
    /// A `---` opener with no closing `---`.
    case unterminated
    /// The block is delimited but its YAML failed to decode (payload describes the failure).
    case undecodable(String)
}

/// Splits a `SKILL.md` into its YAML frontmatter and body. Lives in `ConfigYAML` (the sole
/// C++-interop target) because it decodes YAML — folding block/folded scalars so `SKILL-L001` sees the
/// resolved `description`. Consumers get a pure ``SkillFrontmatter`` and stay interop-free.
public enum FrontmatterParser {
    /// Parse the leading `---…---` block and return the decoded frontmatter plus the remaining body.
    /// Throws a typed ``FrontmatterError`` for malformed input — never an uncaught error.
    public static func parse(_ markdown: String) throws -> (frontmatter: SkillFrontmatter, body: String) {
        // Normalize CRLF so frontmatter scalars and body lines never carry a stray `\r` (SKILL.md is
        // conventionally LF, but a Windows checkout can be CRLF).
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func isDelimiter(_ index: Int) -> Bool {
            lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }
        guard let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            throw FrontmatterError.missing
        }
        guard let closeIndex = lines.indices.dropFirst().first(where: isDelimiter) else {
            throw FrontmatterError.unterminated
        }
        let yaml = lines[1..<closeIndex].joined(separator: "\n")
        let body = closeIndex + 1 < lines.count ? lines[(closeIndex + 1)...].joined(separator: "\n") : ""
        // An empty frontmatter block is valid (all fields nil); YAMLDecoder rejects an empty document.
        guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (SkillFrontmatter(), body)
        }
        do {
            return (try YAMLDecoder().decode(SkillFrontmatter.self, from: yaml), body)
        } catch {
            throw FrontmatterError.undecodable("\(error)")
        }
    }
}
