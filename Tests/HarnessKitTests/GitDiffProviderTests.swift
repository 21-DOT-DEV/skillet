import Testing
import Foundation
@testable import HarnessKit

@Suite("GitDiffProvider — tolerant workspace diff")
struct GitDiffProviderTests {
    private let launcher = SubprocessLauncher()
    private var gitPath: String? {
        BinaryResolver().resolve(flag: nil, envVar: "SKILLET_GIT_BIN", configPath: nil, pathName: "git")?.path
    }
    @discardableResult
    private func git(_ args: [String], in dir: URL) async throws -> Int32 {
        guard let g = gitPath else { return -1 }
        return try await launcher.run(g, ["-C", dir.path] + args, workingDirectory: dir.path,
                                      timeout: .seconds(30), environment: nil, outputLimitBytes: nil).exitCode
    }
    private func repo() async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try await git(["init", "-q"], in: dir)
        _ = try await git(["config", "user.email", "t@t"], in: dir)
        _ = try await git(["config", "user.name", "t"], in: dir)
        _ = try await git(["config", "commit.gpgsign", "false"], in: dir)
        return dir
    }
    private func write(_ dir: URL, _ rel: String, _ s: String) throws {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try s.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("No git binary → empty diff (capture still bundles)")
    func noGit() async {
        let (diff, touched) = await GitDiffProvider(git: nil, launcher: launcher)
            .diff(workspace: FileManager.default.temporaryDirectory, excludePrefix: nil)
        #expect(diff.isEmpty && touched.isEmpty)
    }

    @Test("Not a git repository → empty diff")
    func notARepo() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (diff, touched) = await GitDiffProvider(git: gitPath, launcher: launcher).diff(workspace: dir, excludePrefix: nil)
        #expect(diff.isEmpty && touched.isEmpty)
    }

    @Test("Includes a STAGED new file (diff HEAD), not just working-tree changes")
    func staged() async throws {
        guard gitPath != nil else { return }
        let dir = try await repo(); defer { try? FileManager.default.removeItem(at: dir) }
        try write(dir, "base.txt", "one\n")
        _ = try await git(["add", "."], in: dir)
        _ = try await git(["commit", "-q", "-m", "init"], in: dir)
        try write(dir, "staged.txt", "secret-token\n")
        _ = try await git(["add", "staged.txt"], in: dir)          // staged, uncommitted
        let (diff, touched) = await GitDiffProvider(git: gitPath, launcher: launcher).diff(workspace: dir, excludePrefix: nil)
        #expect(touched.contains("staged.txt"))
        #expect(diff.contains("staged.txt") && diff.contains("secret-token"))
    }

    @Test("Unborn branch (no HEAD): staged files come via the --cached fallback")
    func unbornBranch() async throws {
        guard gitPath != nil else { return }
        let dir = try await repo(); defer { try? FileManager.default.removeItem(at: dir) }
        try write(dir, "first.txt", "hello\n")
        _ = try await git(["add", "first.txt"], in: dir)           // staged, but NO commit → no HEAD
        let (diff, touched) = await GitDiffProvider(git: gitPath, launcher: launcher).diff(workspace: dir, excludePrefix: nil)
        #expect(touched.contains("first.txt"))
        #expect(diff.contains("first.txt") && diff.contains("hello"))
    }

    @Test("Includes untracked files")
    func untracked() async throws {
        guard gitPath != nil else { return }
        let dir = try await repo(); defer { try? FileManager.default.removeItem(at: dir) }
        try write(dir, "new.txt", "brand new\n")                    // never added
        let (_, touched) = await GitDiffProvider(git: gitPath, launcher: launcher).diff(workspace: dir, excludePrefix: nil)
        #expect(touched.contains("new.txt"))
    }

    @Test("excludePrefix drops the sessions-dir subtree from diff + touched")
    func exclude() async throws {
        guard gitPath != nil else { return }
        let dir = try await repo(); defer { try? FileManager.default.removeItem(at: dir) }
        try write(dir, "keep.txt", "keep\n")
        try write(dir, "evals/sessions/old.txt", "prior bundle\n")
        let (diff, touched) = await GitDiffProvider(git: gitPath, launcher: launcher)
            .diff(workspace: dir, excludePrefix: "evals/sessions")
        #expect(touched.contains("keep.txt"))
        #expect(!touched.contains(where: { $0.hasPrefix("evals/sessions") }))
        #expect(!diff.contains("prior bundle"))
    }
}
