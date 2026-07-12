import Testing
import Foundation
@testable import HarnessKit

@Suite("ClaudeCodeAdapter — session locate/export")
struct CaptureLocateTests {
    @Test("Encodes the workspace path like claude-code: every non-[A-Za-z0-9] → -")
    func encoding() {
        #expect(ClaudeCodeAdapter.claudeProjectDirName(for: URL(fileURLWithPath: "/Users/x/Developer/skillet"))
                == "-Users-x-Developer-skillet")
        #expect(ClaudeCodeAdapter.claudeProjectDirName(for: URL(fileURLWithPath: "/tmp/w/.skillet/runs"))
                == "-tmp-w--skillet-runs")
        // Spaces + punctuation are encoded too (the `/._`-only mapping used to leave these unresolved).
        #expect(ClaudeCodeAdapter.claudeProjectDirName(for: URL(fileURLWithPath: "/Users/x/My App (v2)"))
                == "-Users-x-My-App--v2-")   // space, '(' , ')' → -
        #expect(ClaudeCodeAdapter.claudeProjectDirName(for: URL(fileURLWithPath: "/Users/x/a-b_c.d"))
                == "-Users-x-a-b-c-d")       // '-' preserved; '_' and '.' → -
    }

    /// A temp projects-root with `<enc(workspace)>/` created; returns (root, workspace).
    private func makeStore() throws -> (root: URL, workspace: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = URL(fileURLWithPath: "/Users/test/Developer/proj")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(ClaudeCodeAdapter.claudeProjectDirName(for: workspace)),
            withIntermediateDirectories: true)
        return (root, workspace)
    }
    @discardableResult
    private func session(_ root: URL, _ workspace: URL, stem: String, contents: String, mtime: Date) throws -> URL {
        let url = root.appendingPathComponent(ClaudeCodeAdapter.claudeProjectDirName(for: workspace))
            .appendingPathComponent("\(stem).jsonl")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        return url
    }

    @Test("Returns the workspace's sessions newest-first")
    func newestFirst() throws {
        let (root, ws) = try makeStore(); defer { try? FileManager.default.removeItem(at: root) }
        try session(root, ws, stem: "old", contents: "{}", mtime: Date(timeIntervalSince1970: 100))
        try session(root, ws, stem: "new", contents: "{}", mtime: Date(timeIntervalSince1970: 200))
        #expect(ClaudeCodeAdapter.locate(projectsRoot: root, workspace: ws, environment: [:]).map(\.id) == ["new", "old"])
    }

    @Test("Excludes skillet's own in-flight session by $CLAUDE_SESSION_ID")
    func excludesInFlight() throws {
        let (root, ws) = try makeStore(); defer { try? FileManager.default.removeItem(at: root) }
        try session(root, ws, stem: "work", contents: "{}", mtime: Date(timeIntervalSince1970: 100))
        try session(root, ws, stem: "self", contents: "{}", mtime: Date(timeIntervalSince1970: 300))   // newest
        let refs = ClaudeCodeAdapter.locate(projectsRoot: root, workspace: ws, environment: ["CLAUDE_SESSION_ID": "self"])
        #expect(refs.map(\.id) == ["work"])   // the newer "self" is excluded
    }

    @Test("Absent store → empty (command surfaces 'no session found')")
    func absentStore() {
        let refs = ClaudeCodeAdapter.locate(
            projectsRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            workspace: URL(fileURLWithPath: "/no/such"), environment: [:])
        #expect(refs.isEmpty)
    }

    @Test("exportSession reads the located file into a RawTrace")
    func exportsFile() async throws {
        let (root, ws) = try makeStore(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try session(root, ws, stem: "s", contents: #"{"type":"user"}"#, mtime: Date(timeIntervalSince1970: 1))
        let raw = try await ClaudeCodeAdapter().exportSession(NativeSessionRef(id: "s", path: url.path))
        #expect(raw.raw.contains(#""type":"user""#))
    }

    @Test("exportSession on a missing file throws")
    func exportMissing() async {
        await #expect(throws: HarnessError.self) {
            _ = try await ClaudeCodeAdapter().exportSession(NativeSessionRef(id: "x", path: "/no/such/file.jsonl"))
        }
    }

    @Test("exportSession refuses a symlinked session file (no arbitrary-file read via a redirect)")
    func exportRefusesSymlink() async throws {
        let (root, ws) = try makeStore(); defer { try? FileManager.default.removeItem(at: root) }
        let real = try session(root, ws, stem: "real", contents: "{}", mtime: Date(timeIntervalSince1970: 1))
        let link = root.appendingPathComponent(ClaudeCodeAdapter.claudeProjectDirName(for: ws)).appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        await #expect(throws: HarnessError.self) {
            _ = try await ClaudeCodeAdapter().exportSession(NativeSessionRef(id: "link", path: link.path))
        }
    }

    @Test("locate skips symlinked *.jsonl entries (a redirect must not become a capture target)")
    func locateSkipsSymlinks() throws {
        let (root, ws) = try makeStore(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try session(root, ws, stem: "real", contents: "{}", mtime: Date(timeIntervalSince1970: 100))
        let link = root.appendingPathComponent(ClaudeCodeAdapter.claudeProjectDirName(for: ws)).appendingPathComponent("evil.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        #expect(ClaudeCodeAdapter.locate(projectsRoot: root, workspace: ws, environment: [:]).map(\.id) == ["real"])
    }
}
