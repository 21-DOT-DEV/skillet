import Foundation
import EDDCore

/// Finds skillet's project the way git does (design §5.1): resolve the start directory (honoring
/// `-C`), then walk upward to the first `skillet.yaml` (the project root) or `.git` (a boundary).
public struct ProjectLocator: Sendable {
    let probe: DirectoryProbe

    public init(probe: DirectoryProbe = FileSystemProbe()) {
        self.probe = probe
    }

    /// Resolve the directory to start from. `-C` is resolved relative to `cwd`; a missing or
    /// unreadable target is an environment error (exit 3).
    public func resolveStart(dashC: String?, cwd: URL) throws -> URL {
        // Treat cwd as a directory so a relative -C appends to it (not to its parent).
        let base = URL(fileURLWithPath: cwd.path, isDirectory: true)
        guard let dashC, !dashC.isEmpty else { return base.standardizedFileURL }
        let target = URL(fileURLWithPath: dashC, relativeTo: base).standardizedFileURL
        guard probe.isReadableDirectory(target) else {
            throw EDDError.directoryNotFound(path: target.path)
        }
        return target
    }

    /// Walk upward from `start` to the first project marker. `skillet.yaml` wins over `.git` in the
    /// same directory. Returns a `.none` context (with `root == nil`) if neither is found — a benign
    /// state for the root command, which works anywhere.
    public func discover(from start: URL) -> ProjectContext {
        let origin = start.standardizedFileURL
        var directory = origin
        while true {
            if probe.exists(named: "skillet.yaml", in: directory) {
                return ProjectContext(root: directory.path, discoveredVia: .skilletYAML, cwd: origin.path, configPath: nil)
            }
            if probe.exists(named: ".git", in: directory) {
                return ProjectContext(root: directory.path, discoveredVia: .gitBoundary, cwd: origin.path, configPath: nil)
            }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            if parent.path == directory.path { break } // reached the filesystem root
            directory = parent
        }
        return ProjectContext(root: nil, discoveredVia: .none, cwd: origin.path, configPath: nil)
    }

    /// Convenience: resolve `-C` then discover.
    public func locate(dashC: String?, cwd: URL) throws -> ProjectContext {
        try discover(from: resolveStart(dashC: dashC, cwd: cwd))
    }
}
