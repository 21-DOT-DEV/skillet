import Foundation
import Testing

/// Drives the built `skillet score` binary end-to-end (F17): the three output surfaces, the format
/// precedence, and the exit-code contract.
@Suite("skillet score via the binary")
struct ScoreIntegrationTests {
    private func tempDir(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("score-it-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            let url = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return dir
    }
    private func json(_ s: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
    }
    private let sloppy = "This delve into the intricate tapestry shows a crucial testament.\n"

    @Test("--format sarif emits valid SARIF 2.1.0 (schema, tool.driver.rules, located result), exit 0")
    func sarif() async throws {
        let dir = try tempDir(["notes.md": sloppy]); defer { try? FileManager.default.removeItem(at: dir) }
        let out = try await SkilletHarness().run(["score", dir.path, "--format", "sarif"])
        #expect(out.exitCode == 0)
        let obj = json(out.stdout)
        #expect(obj?["version"] as? String == "2.1.0")
        #expect((obj?["$schema"] as? String)?.contains("sarif-2.1.0") == true)
        let run0 = (obj?["runs"] as? [[String: Any]])?.first
        let driver = ((run0?["tool"] as? [String: Any])?["driver"]) as? [String: Any]
        #expect((driver?["name"] as? String) == "skillet")
        #expect(((driver?["rules"] as? [[String: Any]])?.count ?? 0) >= 8)          // static S000–S007 catalog
        let result0 = (run0?["results"] as? [[String: Any]])?.first
        #expect((result0?["ruleId"] as? String) == "SKILL-S001")
        let region = (((result0?["locations"] as? [[String: Any]])?.first?["physicalLocation"]) as? [String: Any])?["region"] as? [String: Any]
        #expect(region?["startLine"] != nil && region?["charOffset"] != nil)        // camelCase, located
    }

    @Test("--format json emits skillet.score/1 with an object-shaped per_rule")
    func jsonFormat() async throws {
        let dir = try tempDir(["notes.md": sloppy]); defer { try? FileManager.default.removeItem(at: dir) }
        let out = try await SkilletHarness().run(["score", dir.path, "--format", "json"])
        #expect(out.exitCode == 0)
        let obj = json(out.stdout)
        #expect(obj?["schema"] as? String == "skillet.score/1")
        let summary = obj?["summary"] as? [String: Any]
        #expect(summary?["per_rule"] is [String: Any])                              // object, not array
        #expect(summary?["files_scored"] as? Int == 1)
    }

    @Test("--json --format sarif → SARIF wins (explicit format beats the generic switch)")
    func precedence() async throws {
        let dir = try tempDir(["notes.md": sloppy]); defer { try? FileManager.default.removeItem(at: dir) }
        let out = try await SkilletHarness().run(["score", dir.path, "--json", "--format", "sarif"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("$schema") && out.stdout.contains("sarif-2.1.0"))
        #expect(!out.stdout.contains("skillet.score/1"))
    }

    @Test("Default (and a bare run) is the human table with a next-step")
    func ttyDefault() async throws {
        let dir = try tempDir(["notes.md": sloppy]); defer { try? FileManager.default.removeItem(at: dir) }
        let out = try await SkilletHarness().run(["score", dir.path])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("SKILL-S001") && out.stdout.contains("MESSAGE"))
        #expect(out.stdout.contains("→ next:"))
    }

    @Test("A single file path is accepted; a clean folder emits valid empty findings, exit 0")
    func fileAndClean() async throws {
        let dir = try tempDir(["clean.md": "The parser reads input and returns output.\n"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try await SkilletHarness().run(["score", dir.path, "--format", "sarif"])
        #expect(folder.exitCode == 0)
        #expect((((json(folder.stdout)?["runs"] as? [[String: Any]])?.first?["results"]) as? [Any])?.isEmpty == true)
        let file = try await SkilletHarness().run(["score", dir.appendingPathComponent("clean.md").path])
        #expect(file.exitCode == 0)
    }

    @Test("Exit codes: missing path → 2, bad path → 3, corrupt config → 4, unknown flag → 2")
    func exitCodes() async throws {
        let harness = try SkilletHarness()
        #expect(try await harness.run(["score"]).exitCode == 2)                          // missing required <path>
        #expect(try await harness.run(["score", "/no/such/path"]).exitCode == 3)         // environment
        #expect(try await harness.run(["score", ".", "--frobnicate"]).exitCode == 2)     // unknown flag

        // Corrupt repo skillet.yaml discovered from the working directory → artifact error (exit 4).
        let bad = try tempDir(["skillet.yaml": "runs:\n  k: [1, 2, 3]\n", "notes.md": sloppy])
        defer { try? FileManager.default.removeItem(at: bad) }
        let out = try await harness.run(["score", bad.path], workingDirectory: bad)
        #expect(out.exitCode == 4)
    }

    @Test("Errors follow the chosen surface: --format json emits JSON on stderr; tty emits a human line")
    func errorFollowsFormat() async throws {
        let harness = try SkilletHarness()
        let asJSON = try await harness.run(["score", "/no/such/path", "--format", "json"])
        #expect(asJSON.exitCode == 3)
        #expect(asJSON.stdout.isEmpty)
        #expect(asJSON.stderr.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"))
        #expect(asJSON.stderr.contains("path_not_found"))
        let asTTY = try await harness.run(["score", "/no/such/path"])
        #expect(asTTY.exitCode == 3)
        #expect(asTTY.stderr.contains("error:") && asTTY.stderr.contains("fix:"))
    }
}
