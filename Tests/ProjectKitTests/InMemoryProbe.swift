import Foundation
import ProjectKit

/// A deterministic, in-memory `DirectoryProbe` for testing the discovery walk without touching the
/// real filesystem. Keyed by standardized absolute path.
struct InMemoryProbe: DirectoryProbe {
    /// directory path → set of entry names present in it.
    var entries: [String: Set<String>] = [:]
    /// directories that count as existing + readable (for `-C` validation).
    var readableDirectories: Set<String> = []

    func exists(named name: String, in directory: URL) -> Bool {
        entries[directory.standardizedFileURL.path]?.contains(name) ?? false
    }

    func isReadableDirectory(_ url: URL) -> Bool {
        readableDirectories.contains(url.standardizedFileURL.path)
    }
}
