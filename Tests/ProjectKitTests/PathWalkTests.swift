import Testing
import Foundation
@testable import ProjectKit

/// The check that no part of a path is a pointer to somewhere else on disk. It used to be skipped
/// whenever the two paths were written differently — and skipping it answered "nothing found", which is
/// the permissive answer. On this platform `/tmp` is itself a pointer to `/private/tmp`, so two spellings
/// of one folder are ordinary rather than exotic.
@Suite("Finding a pointer on a path")
struct PathWalkTests {
    static func makeTree(_ name: String) throws -> URL {
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("skills"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("actual"),
                                                withIntermediateDirectories: true)
        // A pointer that stays *inside* the project: still refused, and still has to be seen.
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("skills/demo"),
                                                   withDestinationURL: root.appendingPathComponent("actual"))
        return root
    }

    @Test("The same folder written two ways gives the same answer")
    func spellingDoesNotChangeTheAnswer() throws {
        let root = try Self.makeTree("walk-spelling"); defer { try? FileManager.default.removeItem(at: root) }
        let target = URL(fileURLWithPath: "/tmp/walk-spelling/skills/demo")
        for spelling in ["/tmp/walk-spelling", "/private/tmp/walk-spelling"] {
            let found = SafeFile.firstSymlinkOnPath(from: URL(fileURLWithPath: spelling), to: target)
            #expect(found?.lastPathComponent == "demo",
                    "written as \(spelling), the pointer at skills/demo went unreported")
        }
    }

    @Test("A folder named in different letter case gives the same answer")
    func letterCaseDoesNotChangeTheAnswer() throws {
        let root = try Self.makeTree("Walk-Casing"); defer { try? FileManager.default.removeItem(at: root) }
        _ = root
        let found = SafeFile.firstSymlinkOnPath(from: URL(fileURLWithPath: "/tmp/walk-casing"),
                                                to: URL(fileURLWithPath: "/tmp/Walk-Casing/skills/demo"))
        #expect(found != nil, "the pointer must be reported, or the path refused — never reported clean")
    }

    /// A folder that is simply not there and a folder we were refused sight of are different questions.
    /// Nothing can exist below the first, so a clean answer is true; the second might hold anything, so a
    /// clean answer would be a guess. Treating them alike broke a caller that legitimately asks about a
    /// path under a folder not created yet.
    @Test("A folder that does not exist answers clean — nothing can be below it")
    func absentBaseAnswersClean() {
        let base = URL(fileURLWithPath: "/tmp/walk-absent-xyz")
        let target = base.appendingPathComponent("fixtures/data.csv")
        #expect(SafeFile.firstSymlinkOnPath(from: base, to: target) == nil)
    }

    @Test("A folder we are not allowed to look into is refused, not waved through")
    func unreadableBaseIsRefused() throws {
        let outer = URL(fileURLWithPath: "/tmp/walk-blocked")
        try? FileManager.default.removeItem(at: outer)
        try FileManager.default.createDirectory(at: outer.appendingPathComponent("inner"),
                                                withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: outer.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outer.path)
            try? FileManager.default.removeItem(at: outer)
        }
        let base = outer.appendingPathComponent("inner")
        let found = SafeFile.firstSymlinkOnPath(from: base, to: base.appendingPathComponent("file.md"))
        #expect(found != nil, "nothing could be checked, so the answer must not be a clean one")
    }

    @Test("An ordinary path with no pointer below the project still passes")
    func plainPathStillPasses() throws {
        let root = try Self.makeTree("walk-plain"); defer { try? FileManager.default.removeItem(at: root) }
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("skills")) == nil)
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("actual")) == nil)
        // A file that does not exist yet is not a pointer, and must not be refused.
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("skills/new.md")) == nil)
    }

    @Test("A path climbing out of the project is still an escape")
    func climbingOutIsStillRefused() throws {
        let root = try Self.makeTree("walk-escape"); defer { try? FileManager.default.removeItem(at: root) }
        #expect(SafeFile.firstSymlinkOnPath(from: root, to: root.appendingPathComponent("../elsewhere")) != nil)
    }
}
