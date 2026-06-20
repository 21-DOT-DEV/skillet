import Foundation

/// A small, injectable seam over the filesystem so project discovery is a deterministic, testable
/// algorithm rather than a tangle of `FileManager` calls (design §11 — effects behind a protocol).
public protocol DirectoryProbe: Sendable {
    /// Whether an entry (file *or* directory) named `name` exists directly inside `directory`.
    func exists(named name: String, in directory: URL) -> Bool
    /// Whether `url` is an existing, readable directory (used to validate `-C`).
    func isReadableDirectory(_ url: URL) -> Bool
}

/// The real, `FileManager`-backed probe.
public struct FileSystemProbe: DirectoryProbe {
    public init() {}

    public func exists(named name: String, in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    public func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue && FileManager.default.isReadableFile(atPath: url.path)
    }
}
