import Testing
import Foundation
@testable import ProjectKit

/// Direct unit tests for the shared filesystem primitive extracted in F17. The suite covers the two
/// fiddly parts — the UTF-8-vs-binary decode heuristic and the size-capped read — plus the symlink /
/// hidden / confinement predicates, so the boundary is protected independently of its consumers.
@Suite("SafeFile — shared confinement + safe-read primitive")
struct SafeFileTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("safefile-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: decodeText

    @Test("Plain UTF-8 and valid multi-byte decode; a NUL byte is binary")
    func decodeBasics() {
        #expect(SafeFile.decodeText(Data("hello".utf8), truncated: false) == "hello")
        #expect(SafeFile.decodeText(Data("café ☕️".utf8), truncated: false) == "café ☕️")
        #expect(SafeFile.decodeText(Data([0x61, 0x00, 0x62]), truncated: false) == nil)   // NUL ⇒ binary
        #expect(SafeFile.decodeText(Data(), truncated: false) == "")                       // empty is empty text
    }

    @Test("Invalid UTF-8 that is NOT a truncation artifact stays binary")
    func decodeInvalidUntruncated() {
        // 0xFF is never valid UTF-8; without the truncation flag there is nothing to forgive.
        #expect(SafeFile.decodeText(Data([0x61, 0xFF]), truncated: false) == nil)
    }

    @Test("A truncated trailing incomplete multi-byte lead is trimmed, not misread as binary")
    func decodeTruncatedBoundaryCut() {
        // "caf" + 0xC3 (the incomplete lead byte of 'é') cut at the cap ⇒ trim the lead ⇒ "caf".
        #expect(SafeFile.decodeText(Data([0x63, 0x61, 0x66, 0xC3]), truncated: true) == "caf")
    }

    @Test("A genuine invalid byte at a truncated boundary still fails to binary (not stripped)")
    func decodeTruncatedGenuineBinary() {
        // 0xFF is neither a continuation byte nor a valid lead — even when truncated, it must stay binary.
        #expect(SafeFile.decodeText(Data([0x61, 0xFF]), truncated: true) == nil)
    }

    // MARK: boundedRead

    @Test("boundedRead returns up to `cap` bytes and the file's full size; nil when unreadable")
    func boundedRead() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("f.txt")
        try Data("hello world".utf8).write(to: file)   // 11 bytes

        let capped = SafeFile.boundedRead(file, cap: 5)
        #expect(capped?.data == Data("hello".utf8))
        #expect(capped?.fullSize == 11)                // full size from metadata, beyond the cap

        let whole = SafeFile.boundedRead(file, cap: 100)
        #expect(whole?.data == Data("hello world".utf8))
        #expect(whole?.fullSize == 11)

        #expect(SafeFile.boundedRead(dir.appendingPathComponent("nope.txt"), cap: 10) == nil)
    }

    @Test("boundedRead: EOF (empty file) is empty Data + fullSize 0; a read error (a directory) is nil")
    func boundedReadEdges() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let empty = dir.appendingPathComponent("empty.txt"); try Data().write(to: empty)
        let e = SafeFile.boundedRead(empty, cap: 10)
        #expect(e?.data == Data() && e?.fullSize == 0)      // EOF is a real, empty read — not "unreadable"
        // A directory opens but `read()` throws (EISDIR) — the fix must return nil, not an empty-but-
        // "successful" Data that would let a caller store/score "" for an unreadable path.
        #expect(SafeFile.boundedRead(dir, cap: 10) == nil)
    }

    // MARK: predicates

    @Test("isSymlink is lstat semantics; isHidden is a leading dot")
    func predicates() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: real)
        let link = dir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(SafeFile.isSymlink(link) == true)
        #expect(SafeFile.isSymlink(real) == false)
        #expect(SafeFile.isHidden(".git") == true)
        #expect(SafeFile.isHidden("references") == false)
    }

    @Test("firstSymlink finds a nested symlink; nil on a clean subtree")
    func firstSymlink() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: sub.appendingPathComponent("real.txt"))
        #expect(SafeFile.firstSymlink(in: dir) == nil)

        try FileManager.default.createSymbolicLink(at: sub.appendingPathComponent("link"),
                                                   withDestinationURL: dir.appendingPathComponent("real.txt"))
        #expect(SafeFile.firstSymlink(in: dir) != nil)
    }

    @Test("firstSymlinkOnPath flags a symlinked component; returns target on escape; nil when confined")
    func firstSymlinkOnPath() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("real/sub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"),
                                                   withDestinationURL: root.appendingPathComponent("real"))

        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("real/sub")) == nil)   // all real
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("link/sub")) != nil)   // crosses a symlink
        let outside = URL(fileURLWithPath: "/etc/hosts")
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: outside) == outside)                               // escape ⇒ returns target
    }

    @Test("firstSymlinkOnPath catches a symlink even with a `..` AFTER it (no standardize-away traversal)")
    func firstSymlinkOnPathDotDotAfterSymlink() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("real"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"),
                                                   withDestinationURL: root.appendingPathComponent("real"))
        // `root/link/../real` standardizes to `root/real` (under root) but routes THROUGH the `link`
        // symlink — must still be flagged, or a `skills_root: link/../real` escapes via the link target.
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("link/../real")) != nil)
        // A benign `..` (no symlink in the way) stays confined → nil.
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("real/../real")) == nil)
    }

    @Test("firstSymlinkOnPath handles the filesystem-root base (/) — a child is confined, not an escape")
    func firstSymlinkOnPathRootBase() {
        let slash = URL(fileURLWithPath: "/")
        #expect(SafeFile.firstSymlinkOnPath(from: slash, to: slash) == nil)                                    // base == target
        #expect(SafeFile.firstSymlinkOnPath(from: slash, to: URL(fileURLWithPath: "/usr")) == nil)             // /usr is a real dir under / (not "//"-escaped)
    }

    @Test("noSymlink is false when any component is a symlink, true when the subtree is clean")
    func noSymlink() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("sub"), withIntermediateDirectories: true)
        #expect(SafeFile.noSymlink(at: real.appendingPathComponent("sub"), under: root) == true)

        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(SafeFile.noSymlink(at: link.appendingPathComponent("sub"), under: root) == false)
    }
}
