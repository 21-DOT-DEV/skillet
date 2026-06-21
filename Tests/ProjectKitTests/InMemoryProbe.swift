import Foundation
import ProjectKit

/// A deterministic, in-memory `DirectoryProbe` for testing discovery/scanning/planning without the
/// real filesystem. Keyed by standardized absolute path.
struct InMemoryProbe: DirectoryProbe {
    /// directory path → set of entry names present in it (files or directories).
    var entries: [String: Set<String>] = [:]
    /// directories that count as existing + readable (for `-C` validation and subdirectory listing).
    var readableDirectories: Set<String> = []

    func exists(named name: String, in directory: URL) -> Bool {
        entries[directory.standardizedFileURL.path]?.contains(name) ?? false
    }

    func isReadableDirectory(_ url: URL) -> Bool {
        readableDirectories.contains(url.standardizedFileURL.path)
    }

    func subdirectories(of directory: URL) -> [URL] {
        let base = directory.standardizedFileURL
        return (entries[base.path] ?? [])
            .map { base.appendingPathComponent($0).standardizedFileURL }
            .filter { readableDirectories.contains($0.path) }
    }
}
