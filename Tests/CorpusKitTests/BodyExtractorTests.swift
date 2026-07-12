import Testing
import Foundation
@testable import CorpusKit

@Suite("BodyExtractor — confined, safe body reads")
struct BodyExtractorTests {
    private func makeWorkspace() throws -> URL {
        let ws = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        return ws
    }
    private func write(_ ws: URL, _ rel: String, _ contents: String) throws {
        let url = ws.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("Reads regular touched files; ignores files not in the touched set")
    func regular() throws {
        let ws = try makeWorkspace(); defer { try? FileManager.default.removeItem(at: ws) }
        try write(ws, "a.txt", "alpha")
        try write(ws, "sub/b.md", "beta")
        try write(ws, "ignored.txt", "nope")   // present on disk but not touched
        #expect(BodyExtractor.extract(touched: ["a.txt", "sub/b.md"], workspace: ws)
                == ["a.txt": "alpha", "sub/b.md": "beta"])
    }

    @Test("Skips a symlinked file (no arbitrary-file read via a redirect)")
    func symlink() throws {
        let ws = try makeWorkspace(); defer { try? FileManager.default.removeItem(at: ws) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "SECRET".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: ws.appendingPathComponent("link.txt"), withDestinationURL: outside)
        #expect(BodyExtractor.extract(touched: ["link.txt"], workspace: ws).isEmpty)
    }

    @Test("Skips a path that escapes the workspace (../)")
    func escape() throws {
        let ws = try makeWorkspace(); defer { try? FileManager.default.removeItem(at: ws) }
        try "SECRET".write(to: ws.deletingLastPathComponent().appendingPathComponent("outside.txt"),
                           atomically: true, encoding: .utf8)
        #expect(BodyExtractor.extract(touched: ["../outside.txt"], workspace: ws).isEmpty)
    }

    @Test("Skips a hard-linked file (another inode, possibly outside the workspace)")
    func hardLink() throws {
        let ws = try makeWorkspace(); defer { try? FileManager.default.removeItem(at: ws) }
        try write(ws, "real.txt", "data")
        try FileManager.default.linkItem(at: ws.appendingPathComponent("real.txt"),
                                         to: ws.appendingPathComponent("hard.txt"))
        // Link count is now 2 for BOTH names, so neither is captured (the confinement is name-agnostic).
        #expect(BodyExtractor.extract(touched: ["real.txt", "hard.txt"], workspace: ws).isEmpty)
    }

    @Test("Skips an oversized (>1 MiB) file, keeps its small sibling")
    func oversized() throws {
        let ws = try makeWorkspace(); defer { try? FileManager.default.removeItem(at: ws) }
        try write(ws, "big.txt", String(repeating: "x", count: (1 << 20) + 1))
        try write(ws, "small.txt", "ok")
        #expect(BodyExtractor.extract(touched: ["big.txt", "small.txt"], workspace: ws) == ["small.txt": "ok"])
    }

    @Test("Skips a touched path that no longer exists")
    func missing() throws {
        let ws = try makeWorkspace(); defer { try? FileManager.default.removeItem(at: ws) }
        #expect(BodyExtractor.extract(touched: ["gone.txt"], workspace: ws).isEmpty)
    }
}
