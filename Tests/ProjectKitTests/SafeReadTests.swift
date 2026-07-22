import Testing
import Foundation
@testable import ProjectKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("SafeFile.readPlainData/Text — the one sanctioned untrusted read (F33 security pass)")
struct SafeReadTests {
    func makeDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skillet-saferead-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func readsAPlainFileBothVariants() throws {
        let dir = try makeDir()
        let url = dir.appendingPathComponent("plain.txt")
        try Data("hello".utf8).write(to: url)
        #expect(try SafeFile.readPlainData(url, cap: 1 << 20).get() == Data("hello".utf8))
        #expect(try SafeFile.readPlainText(url, cap: 1 << 20).get() == "hello")
    }

    @Test func refusesAFIFOInstantlyWithoutOpening() throws {
        // THE hang-class proof: the guard `stat`s before any `open`, so a writer-less FIFO — which
        // blocks `FileHandle`/`String(contentsOf:)` forever — is refused immediately. If this test
        // ever hangs, the guard ordering regressed.
        let dir = try makeDir()
        let path = dir.appendingPathComponent("pipe.yaml").path
        #expect(mkfifo(path, 0o644) == 0)
        #expect(SafeFile.readPlainData(URL(fileURLWithPath: path), cap: 1 << 20) == .failure(.notRegularFile))
    }

    @Test func refusesDirectorySymlinkHardLinkAndMissing() throws {
        let dir = try makeDir()
        #expect(SafeFile.readPlainData(dir, cap: 1 << 20) == .failure(.notRegularFile))          // directory

        let real = dir.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: real)
        let link = dir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(SafeFile.readPlainData(link, cap: 1 << 20) == .failure(.symlink))                // lstat first

        let hard = dir.appendingPathComponent("hard.txt")
        try FileManager.default.linkItem(at: real, to: hard)
        #expect(SafeFile.readPlainData(hard, cap: 1 << 20) == .failure(.hardLink))               // linked inode

        let ghost = dir.appendingPathComponent("ghost.txt")
        #expect(SafeFile.readPlainData(ghost, cap: 1 << 20) == .failure(.notFound))
    }

    @Test func refusesOversizedAndBinary() throws {
        let dir = try makeDir()
        let big = dir.appendingPathComponent("big.txt")
        try Data(repeating: 0x61, count: 32).write(to: big)
        #expect(SafeFile.readPlainData(big, cap: 16) == .failure(.oversized(size: 32, cap: 16)))

        let binary = dir.appendingPathComponent("binary.md")
        try Data([0x00, 0xFF, 0x00]).write(to: binary)
        #expect(SafeFile.readPlainText(binary, cap: 1 << 20) == .failure(.binary))               // text variant only
        #expect(try SafeFile.readPlainData(binary, cap: 1 << 20).get() == Data([0x00, 0xFF, 0x00]))  // data variant passes bytes
    }

    @Test func fullSizeResolutionFailsClosedOnlyWhereProofIsImpossible() {
        // Round 11: when the after-read size lookup fails (file deleted/replaced mid-race), the old
        // fallback reported "size = bytes read", which always passed callers' cap checks — an
        // oversized file could return truncated as success. The provable rule:
        // a verifiable size wins (huge sizes clamp, staying flagged oversized);
        #expect(SafeFile.resolveFullSize(sizeAttr: UInt64.max as Any, dataCount: 10, cap: 100) == Int.max)
        #expect(SafeFile.resolveFullSize(sizeAttr: 42 as Any, dataCount: 10, cap: 100) == 42)
        // an unverifiable size with an UNDER-cap read hit EOF — provably complete, exact count;
        #expect(SafeFile.resolveFullSize(sizeAttr: nil, dataCount: 10, cap: 100) == 10)
        // an unverifiable size with a FILLED cap can't prove there wasn't more — just past the cap,
        // so every caller's `fullSize <= cap` refuses (fail closed exactly where proof is impossible);
        #expect(SafeFile.resolveFullSize(sizeAttr: nil, dataCount: 100, cap: 100) == 101)
        // and the Int.max cap can't overflow.
        #expect(SafeFile.resolveFullSize(sizeAttr: nil, dataCount: Int.max, cap: Int.max) == Int.max)
    }

    @Test func refusalReasonsAreHumanPhrases() {
        // Callers interpolate `reason` straight into disclosures/errors — keep them sentence-shaped.
        #expect(SafeFile.SafeReadRefusal.notRegularFile.reason.contains("not a regular file"))
        #expect(SafeFile.SafeReadRefusal.hardLink.reason.contains("hard link"))
        #expect(SafeFile.SafeReadRefusal.unconfined.reason.contains("escapes"))
        #expect(SafeFile.SafeReadRefusal.oversized(size: 9, cap: 1 << 20).reason.contains("read cap"))
    }

    @Test("readConfinedRegularText reads a confined file but refuses a symlink ON THE PATH as unconfined (round 17)")
    func readConfinedRegularTextConfinesToBase() throws {
        let base = try makeDir(); defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real.md")
        try Data("body".utf8).write(to: real)
        #expect(try SafeFile.readConfinedRegularText(real, base: base, cap: 1 << 20).get() == "body")

        // A symlinked directory component that points OUT of `base` → refused before any read, so host
        // content never siphons in through a symlinked path (the exact BodyExtractor guarantee).
        let outside = base.deletingLastPathComponent().appendingPathComponent("out-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("secret".utf8).write(to: outside.appendingPathComponent("x.md"))
        try FileManager.default.createSymbolicLink(at: base.appendingPathComponent("link"), withDestinationURL: outside)
        #expect(SafeFile.readConfinedRegularText(base.appendingPathComponent("link/x.md"), base: base, cap: 1 << 20)
                == .failure(.unconfined))
    }
}
