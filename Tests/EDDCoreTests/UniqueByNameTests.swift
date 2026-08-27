import Testing
import EDDCore

/// The comparisons join on a test's name, so a set of results in which two entries share one has no
/// defined meaning. This type is how they stop having to decide what to do about it.
@Suite("UniqueByName — a repeated name cannot be expressed")
struct UniqueByNameTests {
    private struct Row { let id: String; let score: Int }

    @Test("Distinct names build, and look up in either order")
    func distinctBuilds() throws {
        let set = try UniqueByName([Row(id: "a", score: 1), Row(id: "b", score: 2)], name: \.id)
        #expect(set.names == ["a", "b"], "order is preserved")
        #expect(set["a"]?.score == 1)
        #expect(set["b"]?.score == 2)
        #expect(set["missing"] == nil)
    }

    @Test("A repeated name refuses, and says which one")
    func repeatedRefuses() throws {
        #expect(throws: RepeatedName(name: "same")) {
            _ = try UniqueByName([Row(id: "same", score: 1), Row(id: "same", score: 2)], name: \.id)
        }
    }

    @Test("The repeat is caught wherever it sits, not only when adjacent")
    func repeatFoundAnywhere() throws {
        #expect(throws: RepeatedName(name: "a")) {
            _ = try UniqueByName([Row(id: "a", score: 1), Row(id: "b", score: 2), Row(id: "a", score: 3)],
                                 name: \.id)
        }
    }

    @Test("Nothing at all is a valid set, not an error")
    func emptyIsFine() throws {
        #expect(try UniqueByName([Row](), name: \.id).isEmpty)
    }

    /// **It can be handed between concurrent tasks.** Swift 6 refuses to move a value across tasks unless
    /// its type says it is safe to. This one carries only what it was given, so it is safe exactly when
    /// its contents are — but that has to be *declared*, or the first place that measures two things at
    /// once fails to compile with no hint of why. Nothing here runs: it compiles only if the declaration
    /// exists, so deleting the declaration breaks the build.
    @Test("A set of safe-to-share results is itself safe to share")
    func sendableWhenContentsAre() {
        func requireSafeToShare<T: Sendable>(_: T.Type) {}
        requireSafeToShare(UniqueByName<Int>.self)
        requireSafeToShare(UniqueByName<String>.self)
    }

    /// **A repeated name in a saved file reads as a bad file, not a crash in the program.** Reading a
    /// results file is not the same as building results in memory: the file came from somewhere else and
    /// may be old, hand-edited, or damaged. Left as-is, the repeated name surfaced through the
    /// catch-all as "something went wrong inside skillet" and exit code 70 — blaming the tool for the
    /// file's problem, and offering no way to fix it.
    @Test("A repeated name can be reported as a bad file, naming the file and the fix")
    func repeatedNameBecomesBadFile() {
        let error = RepeatedName(name: "e1").asInvalidArtifact(path: "benchmark.json")
        guard case let .invalidArtifact(path, reason, fix) = error else {
            Issue.record("a repeated name in a file must report as a bad file, not as anything else")
            return
        }
        #expect(path == "benchmark.json", "the message has to say which file")
        #expect(reason.contains("e1"), "and which name is repeated")
        #expect(fix?.isEmpty == false, "and what to do about it")
    }
}
