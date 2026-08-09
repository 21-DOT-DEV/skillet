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

    /// Two ways of writing one folder. The second spelling is a pointer this test creates, rather than
    /// `/private/tmp` — which is a pointer only on macOS, so relying on it made this pass there and fail
    /// on Linux for a reason that had nothing to do with what is being tested.
    @Test("The same folder written two ways gives the same answer")
    func spellingDoesNotChangeTheAnswer() throws {
        let root = try Self.makeTree("walk-spelling"); defer { try? FileManager.default.removeItem(at: root) }
        let alias = URL(fileURLWithPath: "/tmp/walk-spelling-alias")
        try? FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }

        let target = root.appendingPathComponent("skills/demo")
        for spelling in [root, alias] {
            let found = SafeFile.firstSymlinkOnPath(from: spelling, to: target)
            #expect(found?.lastPathComponent == "demo",
                    "written as \(spelling.path), the pointer at skills/demo went unreported")
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

    /// Provoked with a name longer than any filesystem accepts rather than by removing permissions:
    /// permission bits do not constrain the administrator account, and the container this project's
    /// checks run in uses it, so a permission-based version of this test passed locally and silently
    /// did nothing there. A name that is too long fails the same way for everyone.
    @Test("A folder we cannot look at is refused, not waved through")
    func unreadableBaseIsRefused() throws {
        let base = URL(fileURLWithPath: "/tmp/" + String(repeating: "n", count: 512))
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
