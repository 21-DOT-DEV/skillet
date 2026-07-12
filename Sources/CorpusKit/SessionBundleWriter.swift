import Foundation
import EDDCore

/// Writes one session bundle to `evaluations/<skill>/sessions/<date>-<slug>.*` in the frozen layout.
///
/// **Enforced-path guard:** `write` *requires* a ``SanitizationReport`` — there is no compilable path
/// that writes a bundle without proof it was scrubbed (the report is stamped into `session-meta.json`).
/// The scorer findings (`sarif`, computed over the already-redacted bodies) ride in as the consumer-role
/// `*.audit-input.sarif` (D-2; the producer `*.audit-baseline.sarif` path is a deferred follow-up).
public enum SessionBundleWriter {
    public struct Artifacts: Sendable, Equatable {
        /// Every file written, in creation order.
        public let written: [URL]
        public let bundleStem: String
    }

    public static func write(
        _ artifacts: BundleText,
        sarif: SarifDocument,
        sanitization: SanitizationReport,
        meta: SessionMeta,
        into sessionsDir: URL,
        date: String,
        slug: String,
        force: Bool,
        fileManager: FileManager = .default
    ) throws -> Artifacts {
        let stem = "\(date)-\(slug)"
        func dest(_ suffix: String) -> URL { sessionsDir.appendingPathComponent("\(stem).\(suffix)") }
        let transcriptURL = dest("transcript.md")
        let diffURL       = dest("diff")
        let bodiesURL     = dest("bodies.json")
        let traceURL      = dest("trace.json")
        let sarifURL      = dest("\(SarifRole.auditInput.rawValue).sarif")   // consumer role (D-2)
        let metaURL       = dest("session-meta.json")
        let allDests      = [transcriptURL, diffURL, bodiesURL, traceURL, sarifURL, metaURL]

        do {
            try fileManager.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        } catch {
            throw CorpusError.writeFailed(path: sessionsDir.lastPathComponent, reason: "could not create sessions dir: \(error)")
        }

        // Collision check — collect *all* existing destinations before throwing, so the remedy lists
        // everything the user would need to remove (or re-run with --force).
        if !force {
            let existing = allDests.filter { fileManager.fileExists(atPath: $0.path) }.map(\.lastPathComponent)
            if !existing.isEmpty { throw CorpusError.destinationExists(paths: existing) }
        }

        // Stamp the scan provenance from the REQUIRED report (this is what makes the guard meaningful:
        // the written meta always reflects the actual scrub).
        var stampedMeta = meta
        stampedMeta.fields["sanitization"] = .object(sanitization.summary)

        // Sorted + pretty JSON to match the existing corpus byte-shape; ISO8601 dates so `trace.json`
        // timestamps read like `session-meta.json`'s `captured_at` rather than raw doubles (log-b).
        // bodies + meta: keys **verbatim** — this protects `SessionMeta`'s `RawJSONObject` unknown-key
        // round-trip (a frozen-format MUST) and leaves body-file-path keys untouched.
        // `.withoutEscapingSlashes`: path keys (`src/main.swift`) don't become `src\/main.swift`.
        let json = JSONEncoder()
        json.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        json.dateEncodingStrategy = .iso8601
        // `trace.json` is the `skillet.trace/1` wire format → **snake_case** keys (`harness_version`,
        // `started_at`, …) so it round-trips via `SkilletJSON.decode` and matches the format `TraceTests`
        // verifies. A dedicated encoder keeps convertToSnakeCase off bodies/meta above.
        let traceJSON = JSONEncoder()
        traceJSON.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        traceJSON.dateEncodingStrategy = .iso8601
        traceJSON.keyEncodingStrategy = .convertToSnakeCase

        var written: [URL] = []
        func put(_ text: String, _ url: URL) throws {
            do { try Data(text.utf8).write(to: url, options: .atomic) }
            catch { throw CorpusError.writeFailed(path: url.lastPathComponent, reason: "\(error)") }
            written.append(url)
        }
        func encode<T: Encodable>(_ value: T, with encoder: JSONEncoder) throws -> String {
            do { return String(decoding: try encoder.encode(value), as: UTF8.self) }
            catch { throw CorpusError.writeFailed(path: "\(stem) (encode)", reason: "\(error)") }
        }

        try put(artifacts.transcript, transcriptURL)
        try put(artifacts.diff, diffURL)
        try put(try encode(artifacts.bodies, with: json), bodiesURL)
        try put(try encode(artifacts.trace, with: traceJSON), traceURL)   // snake_case skillet.trace/1
        // SarifDocument owns its 2.1.0 serialization — but it can throw (e.g. a non-finite Double). Wrap
        // that like the JSON `encode` helper so the command sees a `CorpusError` (→ artifact exit 4), not
        // an unmapped error that would fall through to a generic/usage exit.
        let sarifJSON: String
        do { sarifJSON = try sarif.jsonString() }
        catch { throw CorpusError.writeFailed(path: sarifURL.lastPathComponent + " (encode)", reason: "\(error)") }
        try put(sarifJSON, sarifURL)
        try put(try encode(stampedMeta, with: json), metaURL)

        return Artifacts(written: written, bundleStem: stem)
    }
}
