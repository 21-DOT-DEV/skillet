import Foundation

/// Matches a bundle-relative artifact path against `sanitize.exempt_paths` patterns — a **subset** of
/// gitignore-style glob, whole-segment (plan 014 §4). A pattern matches when it (a) equals the path
/// exactly, (b) names a directory whose subtree contains the path (`fixtures` or `fixtures/` →
/// `fixtures/x.md`), or (c) is a glob where `*` matches within one path segment and `**` matches across
/// segments (`fixtures/*.md`, `**/*.env`). **Not** supported (unlike full gitignore): `?` (single char)
/// and `[abc]` character classes — write an explicit `*`/`**` pattern, or use betterleaks' own allowlist.
///
/// Globs — not regex — are deliberate. `exempt_paths` is a hand-written YAML list, and a stray regex
/// `.*` that silently exempts *everything* would defeat the redactor (a security footgun); gitignore-
/// style globs are the convention users already know and match skillet's own whole-segment
/// `scorers.vendored_prefixes`. betterleaks' own regex allowlist (`.betterleaks.toml`) is a separate,
/// still-honored layer for power users.
enum ExemptMatcher {
    /// Whether a pattern would exempt essentially *any* path — a blanket bypass the constitution forbids
    /// (`exempt_paths` must be surgical; there is no `--no-sanitize`). True when the pattern carries **no
    /// literal anchor**: stripping the glob metacharacter (`*`) and separators (`/`) leaves nothing —
    /// `**`, `*`, `*/*`, `**/*` all match arbitrary paths. Extension- or directory-anchored patterns
    /// (`*.md`, `fixtures/**`) keep a literal and stay surgical. Callers must fail closed on `true`.
    static func isOverBroad(_ pattern: String) -> Bool {
        let trimmed = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
        guard !trimmed.isEmpty else { return false }   // empty / bare "/" is a no-op (isExempt skips it), not a bypass
        return trimmed.replacingOccurrences(of: "*", with: "")
                      .replacingOccurrences(of: "/", with: "")
                      .isEmpty
    }

    static func isExempt(_ path: String, patterns: Set<String>) -> Bool {
        for raw in patterns {
            let pattern = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            guard !pattern.isEmpty else { continue }
            if path == pattern { return true }                        // exact
            if pattern.contains("*") {
                if globMatches(pattern, path) { return true }         // glob
            } else if path.hasPrefix(pattern + "/") {
                return true                                           // directory subtree (whole-segment)
            }
        }
        return false
    }

    /// gitignore-style glob → anchored regex. `**/` matches **zero or more** leading/intervening
    /// segments (so `**/foo` also matches a root-level `foo`, "the same as pattern `foo`", and `a/**/b`
    /// matches `a/b`); a trailing/lone `**` → `.*` (crosses `/`); a single `*` → `[^/]*` (within one
    /// segment). Every other character is regex-escaped and the whole thing is anchored `^…$`, so a
    /// pattern like `fixtures/**` (`^fixtures/.*$`) can never overmatch a sibling such as `fixturesX`.
    private static func globMatches(_ pattern: String, _ path: String) -> Bool {
        let chars = Array(pattern)
        var rx = "^"
        var i = 0
        while i < chars.count {
            if chars[i] == "*" {
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    if i + 2 < chars.count, chars[i + 2] == "/" {
                        rx += "(?:.*/)?"; i += 3           // `**/` → zero-or-more segments (incl. none)
                    } else {
                        rx += ".*"; i += 2                 // trailing/lone `**` → anything, crossing `/`
                    }
                } else {
                    rx += "[^/]*"; i += 1                  // `*` → within one segment
                }
            } else {
                rx += NSRegularExpression.escapedPattern(for: String(chars[i]))
                i += 1
            }
        }
        rx += "$"
        guard let re = try? NSRegularExpression(pattern: rx) else { return false }
        return re.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }
}
