import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// F43 — the throwaway copy, the records, and what is left behind. Every test here is free unless its name says otherwise: the offline stand-ins answer
/// instead of a model. Setup is shared in `IterateFixture`.
@Suite("skillet iterate — the throwaway copy, the records, and what is left behind", .tags(.integration))
struct IterateCopyTests {
    // MARK: - the copy, and what it leaves behind

    @Test("The copy is gone from git's own list afterwards, and left no branch behind")
    func copyAndBranchAreGone() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let branchesBefore = try await IterateFixture.run("git", ["branch", "--list"], in: root)
        _ = try await IterateFixture.iterate(root, map)
        let copies = try await IterateFixture.run("git", ["worktree", "list"], in: root)
        #expect(copies.components(separatedBy: "\n").filter { !$0.isEmpty }.count == 1,
                "removing the folder is not enough — git's own bookkeeping must be clear too")
        #expect(try await IterateFixture.run("git", ["branch", "--list"], in: root) == branchesBefore,
                "no branch was created, so none can be left behind")
    }

    @Test("--keep-worktree retains the copy and prints where it is")
    func keepsCopyOnRequest() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--keep-worktree"])
        let line = out.stdout.components(separatedBy: "\n").first { $0.contains("copy kept") }
        let path = try #require(line?.components(separatedBy: "copy kept").last?.trimmingCharacters(in: .whitespaces))
        #expect(FileManager.default.fileExists(atPath: path), "it says where, and it is there")
        _ = try await IterateFixture.run("git", ["worktree", "remove", "--force", path], in: root)
    }

    /// **Asking to keep the copy is useless if you are not told where it went.** The location was printed
    /// for a person and left out of the machine-readable result entirely, so anything scripted asked for
    /// the copy and then had to guess at a name containing a random identifier. Absent when no copy was
    /// kept, so its presence means what it says.
    @Test("--json says where the kept copy is, and says nothing when none was kept")
    func machineReadableNamesKeptCopy() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--keep-worktree", "--json"])
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any])
        let path = try #require(json["kept_copy"] as? String, "asking to keep the copy must report where it is")
        #expect(FileManager.default.fileExists(atPath: path), "and the reported place must exist")
        _ = try await IterateFixture.run("git", ["worktree", "remove", "--force", path], in: root)

        let plain = try await IterateFixture.iterate(root, map, ["--json"])
        let plainJSON = try #require(try JSONSerialization.jsonObject(with: Data(plain.stdout.utf8)) as? [String: Any])
        #expect(plainJSON["kept_copy"] == nil, "no copy was kept, so there is no place to report")
    }

    @Test("Both measurements survive the copy being removed, and neither overwrites the other")
    func bothArmsRecordsSurvive() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        _ = try await IterateFixture.iterate(root, map)
        let runs = root.appendingPathComponent(".skillet/runs")
        let all = FileManager.default.enumerator(atPath: runs.path)?.allObjects as? [String] ?? []
        #expect(all.contains { $0.contains("before/") }, "the first measurement's records are here")
        #expect(all.contains { $0.contains("after/") }, "and so are the second's — not overwritten")
    }

    // MARK: - where the records go, and what a failure leaves behind

    @Test("A cache folder that is a shortcut elsewhere is refused — traces never leave the project")
    func symlinkedCacheRefuses() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let outside = try Fixture.makeTempDirectory(); defer { Fixture.remove(outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(".skillet/runs"), withDestinationURL: outside)

        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 4)
        #expect(out.stderr.contains("crosses a symlink"), "the same refusal the measuring command gives")
        let escaped = try FileManager.default.contentsOfDirectory(atPath: outside.path)
        #expect(escaped.isEmpty, "not one transcript was written outside the project")
    }

    /// Cleanup runs on the way out of a *failure*, not only a success — and it is waited for. Started and
    /// abandoned, it lost the race with the process exiting, leaving a dead entry in git's own list that
    /// does not clear itself: git only sweeps records older than `gc.worktreePruneExpire`, three months
    /// by default. `git worktree remove` deletes the folder and the record together, so the record
    /// standing for both is exact.
    @Test("A failure after the copy is made still removes the copy")
    func failureStillRemovesTheCopy() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let outside = try Fixture.makeTempDirectory(); defer { Fixture.remove(outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(".skillet/runs"), withDestinationURL: outside)

        let out = try await IterateFixture.iterate(root, map)
        #expect(out.exitCode == 4, "it failed past the point where the copy exists")
        let copies = try await IterateFixture.run("git", ["worktree", "list"], in: root)
        #expect(!copies.contains("skillet-iterate"), "no dead entry was left to accumulate")
        #expect(copies.components(separatedBy: "\n").filter { !$0.isEmpty }.count == 1)
    }

    @Test("--dry-run leaves no copy behind either")
    func previewLeavesNoCopy() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        _ = try await IterateFixture.iterate(root, map, ["--dry-run"])
        let copies = try await IterateFixture.run("git", ["worktree", "list"], in: root)
        #expect(!copies.contains("skillet-iterate"))
        #expect(copies.components(separatedBy: "\n").filter { !$0.isEmpty }.count == 1)
    }

    // MARK: - a preview that leaves something behind says so

    @Test("--dry-run --keep-worktree names the copy it kept")
    func previewNamesTheCopyItKeeps() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--dry-run", "--keep-worktree"])
        #expect(out.exitCode == 0)
        let line = out.stdout.components(separatedBy: "\n").first { $0.contains("copy kept") }
        let path = try #require(line?.components(separatedBy: "copy kept").last?
            .trimmingCharacters(in: .whitespaces), "a preview that keeps a copy must say where it is")
        #expect(FileManager.default.fileExists(atPath: path), "it says where, and it is there")
        _ = try await IterateFixture.run("git", ["worktree", "remove", "--force", path], in: root)
    }

    // MARK: - two runs, one after another

    /// Each run stamps its records and its copy with a random component, so two runs cannot land in the
    /// same folder. Drop that and the second run overwrites the first's records — which is the guarantee
    /// D5 exists for, and whose existing test only covers the two halves *within* one run.
    ///
    /// **The random component is the whole identifier, not a prefix of it.** It was eight characters,
    /// defended on the grounds that the timestamp beside it made a clash need two runs in the same second.
    /// That weighed how likely a clash was without weighing what one *does*: asking for a folder that
    /// already exists succeeds silently, so a second run writes its records into the first's folder and
    /// preparing a workspace there deletes what is already in it. This test cannot force a clash — it
    /// would have to win a one-in-four-billion race — so it covers the outcome that holds either way, and
    /// says plainly what it does not cover.
    @Test("Two runs in a row keep separate records and separate copies")
    func consecutiveRunsDoNotCollide() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        _ = try await IterateFixture.iterate(root, map, ["--runs", "1"])
        _ = try await IterateFixture.iterate(root, map, ["--runs", "1"])
        let runs = root.appendingPathComponent(".skillet/runs")
        let folders = (try FileManager.default.contentsOfDirectory(atPath: runs.path))
            .filter { $0.hasPrefix("iterate-") }
        #expect(folders.count == 2, "the second run must not write into the first's folder")
        let copies = try await IterateFixture.run("git", ["worktree", "list"], in: root)
        #expect(!copies.contains("skillet-iterate"), "and both copies are gone afterwards")
    }

    // MARK: - what a failed clean-up says

    /// Deletion can fail on a lock or a permission problem. It used to print a complete successful
    /// report, exit 0, and say nothing, leaving the folder and an entry in git's own list of copies —
    /// which does not clear itself for three months.
    @Test("A copy that could not be removed is disclosed, in both what is printed and what a script reads")
    func failedCleanupIsDisclosed() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves); defer { Fixture.remove(root) }
        // A git that behaves normally except that removing a copy always fails.
        // Inside the ignored scratch folder: anywhere else in the project makes the tree dirty, and
        // this command refuses a dirty tree before it ever reaches the part under test.
        let fake = root.appendingPathComponent(".skillet/fake-git")
        try "#!/bin/sh\nif [ \"$1\" = worktree ] && [ \"$2\" = remove ]; then exit 128; fi\nexec git \"$@\"\n"
            .write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "iterate", "demo", "--proposals", "fix.json", "--replay",
             "--replay-map", map, "--yes", "--runs", "1"],
            environment: ["SKILLET_GIT_BIN": fake.path])
        #expect(out.exitCode == 0, "the measurement succeeded; tidying up failing must not change that")
        #expect(out.stdout.contains("! throwaway copy:"), "the printed result says so")
        #expect(out.stdout.contains("git worktree remove --force"), "and hands over the way to clear it")

        let json = try await SkilletHarness().run(
            ["-C", root.path, "iterate", "demo", "--proposals", "fix.json", "--replay",
             "--replay-map", map, "--yes", "--runs", "1", "--json"],
            environment: ["SKILLET_GIT_BIN": fake.path])
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(json.stdout.utf8)) as? [String: Any])
        let disclosed = try #require(payload["disclosures"] as? [[String: Any]])
        // `#expect` does not stop the test, so indexing straight into this list would TRAP rather than
        // fail when it is empty — taking the whole test process down instead of reporting. Required, not
        // subscripted.
        let first = try #require(disclosed.first,
                                 "a script that never reads the error stream still learns of it")
        #expect(disclosed.count == 1)
        #expect(first["subject"] as? String == "throwaway copy")

        // Clear what the fake git refused to.
        let copies = try await IterateFixture.run("git", ["worktree", "list"], in: root)
        for line in copies.components(separatedBy: "\n") where line.contains("skillet-iterate") {
            let path = String(line.prefix(while: { $0 != " " }))
            _ = try? await IterateFixture.run("git", ["worktree", "remove", "--force", path], in: root)
        }
    }

}

/// **Asking to keep the copy is exactly when you want to know where it is.**
///
/// To measure a skill twice without touching your real files, this tool makes a separate copy of the
/// project and works inside it. A switch asks for that copy to be left behind so you can look at it. When
/// the measurement then fails, the copy is kept — and nothing used to say where, so the one case where you
/// most want to open it was the case where you could not find it.
@Suite("A kept copy is reported even when the run fails", .tags(.integration))
struct KeptCopyOnFailureTests {
    @Test("A failed run that kept its copy says where the copy is")
    func failedRunNamesTheKeptCopy() async throws {
        // A draft quoting a passage the file does not contain: refused after the copy is made.
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves, excerpt: "a passage that is not in the file")
        defer { Fixture.remove(root) }
        let out = try await IterateFixture.iterate(root, map, ["--keep-worktree"])
        #expect(out.exitCode != 0, "the run failed, which is the situation being covered")
        let line = out.stderr.components(separatedBy: "\n").first { $0.contains("throwaway copy was kept") }
        let said = try #require(line, "a failed run that kept its copy must say where it is: \(out.stderr)")
        let path = String(said[(said.range(of: "is at ")!.upperBound)...])
            .components(separatedBy: " ").first ?? ""
        #expect(FileManager.default.fileExists(atPath: path), "and the place it names must exist")
        _ = try? await IterateFixture.run("git", ["worktree", "remove", "--force", path], in: root)
    }
}

/// **A failed command is quoted as it was actually run.**
///
/// When a step that manages the separate working copy fails, the message quotes the command that failed.
/// It quoted only the first two words — `git worktree add` — dropping the path it was given and everything
/// after, so the command shown was one nobody had run and could not be repeated to see the failure.
/// Guidance for command-line tools is consistent that a failure should carry enough context to reproduce
/// it; a truncated quotation reads as precise while being unusable.
@Suite("A failed version-control command is quoted in full", .tags(.integration))
struct GitCommandQuotedInFullTests {
    /// A stand-in for the version-control program that behaves normally except for the one operation this
    /// test needs to fail. Pointed at by the setting that names which program to use.
    private func failingOnly(_ operation: String, in directory: URL) throws -> String {
        let script = directory.appendingPathComponent("git-stub.sh")
        try """
        #!/bin/sh
        if [ "$1" = "\(operation)" ] && [ "$2" = "add" ]; then
          echo "stub: refusing \(operation) add" >&2
          exit 3
        fi
        exec /usr/bin/git "$@"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    @Test("The quoted command carries its arguments, not just its first two words")
    func quotesWholeCommand() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves)
        defer { Fixture.remove(root) }
        let elsewhere = try Fixture.makeTempDirectory(); defer { Fixture.remove(elsewhere) }
        let stub = try failingOnly("worktree", in: elsewhere)

        let out = try await IterateFixture.iterate(root, map, [], environment: ["SKILLET_GIT_BIN": stub])
        #expect(out.stderr.contains("git worktree add"), "it failed where intended: \(out.stderr)")
        #expect(out.stderr.contains("--detach"),
                "and the quoted command must carry its arguments: \(out.stderr)")
        #expect(out.stderr.contains("HEAD"), "including the point the copy is made from")
    }
}
