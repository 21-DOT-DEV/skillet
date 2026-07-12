import Testing
import Foundation
import EDDCore
import TraceKit
@testable import CorpusKit

@Suite("SessionBundleWriter")
struct SessionBundleWriterTests {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func sampleBundle() -> BundleText {
        let trace = Trace(
            harness: "claude-code", harnessVersion: "1",
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1),
            turns: [Turn(role: .user, text: "hi", at: Date(timeIntervalSince1970: 0))],
            skillInvocations: [], workspaceDiff: WorkspaceDiff())
        return BundleText(transcript: "## User\nhi\n", diff: "diff text", bodies: ["a.md": "clean body"], trace: trace)
    }
    private func meta() -> SessionMeta {
        SessionMeta(id: "2026-07-11-x", skill: "docc-articles", skillVersion: "1.0.0",
                    model: "claude-opus-4-8", harness: "claude-code", capturedAt: "2026-07-11T00:00:00Z")
    }
    private func write(into dir: URL, report: SanitizationReport, force: Bool) throws -> SessionBundleWriter.Artifacts {
        try SessionBundleWriter.write(sampleBundle(), sarif: SarifDocument(runs: []), sanitization: report,
                                      meta: meta(), into: dir, date: "2026-07-11", slug: "x", force: force)
    }

    @Test("Writes all six bundle files with the <date>-<slug> stem")
    func writesAllSix() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = try write(into: dir, report: SanitizationReport(scanner: "betterleaks", version: "1.6.1", redactions: 0), force: false)
        #expect(Set(a.written.map(\.lastPathComponent)) == [
            "2026-07-11-x.transcript.md", "2026-07-11-x.diff", "2026-07-11-x.bodies.json",
            "2026-07-11-x.trace.json", "2026-07-11-x.audit-input.sarif", "2026-07-11-x.session-meta.json"])
        for u in a.written { #expect(FileManager.default.fileExists(atPath: u.path)) }
    }

    @Test("session-meta.json carries the scan provenance from the required report")
    func stampsSanitization() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write(into: dir, report: SanitizationReport(scanner: "betterleaks", version: "1.6.1", redactions: 3), force: false)
        let text = try String(contentsOf: dir.appendingPathComponent("2026-07-11-x.session-meta.json"), encoding: .utf8)
        #expect(text.contains(#""scanner" : "betterleaks""#))
        #expect(text.contains(#""redactions" : 3"#))
        #expect(text.contains(#""version" : "1.6.1""#))
    }

    @Test("Refuses to overwrite an existing bundle; --force clobbers")
    func collisionAndForce() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write(into: dir, report: SanitizationReport(scanner: "none"), force: false)
        #expect(throws: CorpusError.self) { try write(into: dir, report: SanitizationReport(scanner: "none"), force: false) }
        #expect(try write(into: dir, report: SanitizationReport(scanner: "none"), force: true).written.count == 6)
    }

    @Test("bodies.json + trace.json are valid JSON and round-trip")
    func bundleFilesValid() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write(into: dir, report: SanitizationReport(scanner: "none"), force: false)
        let bodies = try JSONDecoder().decode([String: String].self,
                        from: Data(contentsOf: dir.appendingPathComponent("2026-07-11-x.bodies.json")))
        #expect(bodies["a.md"] == "clean body")
        // trace.json is the snake_case `skillet.trace/1` wire format → it round-trips via SkilletJSON.decode.
        let traceText = try String(contentsOf: dir.appendingPathComponent("2026-07-11-x.trace.json"), encoding: .utf8)
        let trace = try SkilletJSON.decode(Trace.self, from: traceText)
        #expect(trace.turns.first?.text == "hi")
        #expect(traceText.contains("harness_version") && !traceText.contains("harnessVersion"))   // snake_case keys
    }

    @Test("bodies.json / trace.json don't escape forward slashes in paths (matches SARIF)")
    func doesNotEscapeSlashes() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let trace = Trace(
            harness: "claude-code", harnessVersion: "1",
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1),
            turns: [Turn(role: .user, text: "hi", at: Date(timeIntervalSince1970: 0))],
            skillInvocations: [], workspaceDiff: WorkspaceDiff(added: ["src/new.swift"]))
        let bundle = BundleText(transcript: "t", diff: "d", bodies: ["src/main.swift": "code"], trace: trace)
        _ = try SessionBundleWriter.write(bundle, sarif: SarifDocument(runs: []),
            sanitization: SanitizationReport(scanner: "none"), meta: meta(),
            into: dir, date: "2026-07-11", slug: "x", force: false)
        let bodies = try String(contentsOf: dir.appendingPathComponent("2026-07-11-x.bodies.json"), encoding: .utf8)
        #expect(bodies.contains("src/main.swift") && !bodies.contains(#"src\/main.swift"#))
        let traceJSON = try String(contentsOf: dir.appendingPathComponent("2026-07-11-x.trace.json"), encoding: .utf8)
        #expect(traceJSON.contains("src/new.swift") && !traceJSON.contains(#"\/"#))
    }
}
