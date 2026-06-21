import Foundation
import EDDCore

/// The effectful seam for applying an ``InitPlan`` — real on disk, fakeable in tests.
public protocol FileSystemWriter: Sendable {
    func createDirectory(_ url: URL) throws
    func writeFile(_ url: URL, contents: String) throws
}

public struct RealFileSystemWriter: FileSystemWriter {
    public init() {}

    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func writeFile(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Applies an ``InitPlan`` and reports what was created vs. skipped (paths relative to the root).
public struct InitExecutor: Sendable {
    let writer: FileSystemWriter

    public init(writer: FileSystemWriter = RealFileSystemWriter()) {
        self.writer = writer
    }

    public func apply(_ plan: InitPlan, root: URL) throws -> InitReport {
        var created: [String] = []
        for action in plan.actions {
            switch action {
            case let .createDirectory(url):
                try writer.createDirectory(url)
            case let .writeFile(url, contents):
                try writer.writeFile(url, contents: contents)
            }
            created.append(Self.relativePath(action.url, to: root))
        }
        let skipped = plan.skipped.map { Self.relativePath($0, to: root) }
        return InitReport(created: created.sorted(), skipped: skipped.sorted(), skills: plan.skills)
    }

    static func relativePath(_ url: URL, to root: URL) -> String {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(base + "/") { return String(path.dropFirst(base.count + 1)) }
        return path
    }
}
