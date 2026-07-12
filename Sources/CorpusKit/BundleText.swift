import TraceKit

/// The text-bearing artifacts of one capture, flowing as a single value through the pipeline
/// (assemble → sanitize → score → write). The `trace` is the **structured** ``Trace`` — not flattened
/// to text — so (a) secrets in `turns[].toolCalls[].input` (tool arguments, a documented leak vector)
/// are reachable to the scrubber and (b) `trace.json` re-encodes validly after redaction.
public struct BundleText: Sendable, Equatable {
    public var transcript: String
    public var diff: String
    /// Produced-file bodies, keyed by bundle-relative path. Both keys and values are scrubbed — a secret
    /// can hide in a filename (e.g. `ghp_….txt`), and an unscrubbed key would leak into `bodies.json`
    /// and the scorer's SARIF `uri`.
    public var bodies: [String: String]
    public var trace: Trace

    public init(transcript: String, diff: String, bodies: [String: String], trace: Trace) {
        self.transcript = transcript
        self.diff = diff
        self.bodies = bodies
        self.trace = trace
    }

    /// The artifacts as `(path, text)` scan inputs for the secret scanner — one entry per text-bearing
    /// artifact, each labeled with a stable path so findings carry a filename (drives exempt-path
    /// filtering). The structured trace is flattened to a single scannable blob under `"trace.json"`.
    public var scanInputs: [(path: String, text: String)] {
        var inputs: [(String, String)] = [
            ("transcript.md", transcript),
            ("diff", diff),
        ]
        for (path, text) in bodies.sorted(by: { $0.key < $1.key }) {
            // Scan the KEY (a bundle-relative path) alongside the content, both under the REAL path label:
            // a secret in a *filename* (`ghp_….txt`) is (a) detected + redacted from the key/SARIF uri and
            // (b) reported under its real path — so `exempt_paths: [that path]` can target it, rather than
            // a synthetic "paths" label a user can't name (finding). Trace paths ride in via `trace.scannableText`.
            inputs.append((path, path + "\n" + text))
        }
        inputs.append(("trace.json", trace.scannableText))
        return inputs
    }

    /// Apply a value-based scrub to **every** text field — the two prose artifacts, each body value,
    /// and every `String` in the structured trace (`turns[].text`, `toolCalls[].input`, touched paths).
    public func redacting(_ transform: (String) -> String) -> BundleText {
        // Scrub BOTH keys and values: a secret in a filename must not survive as a dictionary key (it
        // would leak into `bodies.json` and, through the scorer's temp staging, into the SARIF `uri`).
        // `transform` only rewrites *detected* secrets, so ordinary paths pass through unchanged. Process
        // in sorted order and disambiguate any collision (two distinct paths can scrub to the same key —
        // `ghp_a.txt` & `ghp_b.txt` → `[REDACTED:github-pat].txt`) so no body is silently overwritten.
        var scrubbedBodies: [String: String] = [:]
        for (key, value) in bodies.sorted(by: { $0.key < $1.key }) {
            scrubbedBodies[Self.uniqueKey(transform(key), taken: scrubbedBodies)] = transform(value)
        }
        return BundleText(
            transcript: transform(transcript),
            diff: transform(diff),
            bodies: scrubbedBodies,
            trace: trace.redacting(transform))
    }

    /// Return `key`, or `key` with `-2`/`-3`/… inserted before its extension if it already exists in
    /// `taken` — so two original paths that redact to the same key don't overwrite each other.
    private static func uniqueKey(_ key: String, taken: [String: String]) -> String {
        guard taken[key] != nil else { return key }
        let dot = key.lastIndex(of: "."), slash = key.lastIndex(of: "/")
        let hasExt = dot != nil && (slash == nil || dot! > slash!)   // a real extension, not a dir dot
        let stem = hasExt ? String(key[..<dot!]) : key
        let ext  = hasExt ? String(key[dot!...]) : ""                // includes the leading dot
        var n = 2
        while taken["\(stem)-\(n)\(ext)"] != nil { n += 1 }
        return "\(stem)-\(n)\(ext)"
    }
}
