import Foundation

/// Builds throwaway, per-test project directories so integration tests are isolated and
/// parallel-safe. Each call returns a unique temp directory; remove it with `defer`.
enum Fixture {
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-it-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A temp directory containing a `skillet.yaml` marker — a discoverable project root.
    static func makeProject() throws -> URL {
        let root = try makeTempDirectory()
        try "project:\n  skills_root: skills\n".write(
            to: root.appendingPathComponent("skillet.yaml"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
