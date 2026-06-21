import Foundation

/// Reads repo docs from a test (located via `#filePath`, so it's working-directory-independent) and
/// extracts internal markdown links for the link-check.
enum DocFile {
    // <root>/Tests/IntegrationTests/DocFile.swift → up 3 → repo root
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func read(_ name: String) throws -> String {
        try String(contentsOf: root.appending(path: name), encoding: .utf8)
    }

    /// Relative markdown link targets (`](path)`), with anchors stripped and URLs/mailto skipped.
    static func internalLinks(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\]\(([^)\s]+)\)"#) else { return [] }
        let ns = text as NSString
        var links: [String] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1))
            let path = String(raw.split(separator: "#").first ?? "")
            if path.isEmpty { continue }
            if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("mailto:") { continue }
            links.append(path)
        }
        return links
    }
}
