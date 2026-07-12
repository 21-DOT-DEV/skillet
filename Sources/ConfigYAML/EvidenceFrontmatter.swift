import Foundation
import YAML
import EDDCore

/// Serialization errors from an evidence file's YAML frontmatter — owned **here at the seam**, never in
/// pure `EDDCore` (a YAML/frontmatter concept must not leak into the core; D4). The `friction`/`triage`
/// commands translate these to `EDDError.invalidArtifact` at the boundary.
public enum ConfigError: Error, Equatable {
    /// No `---` block, an unterminated block, empty frontmatter, or YAML that won't parse.
    case malformedFrontmatter(String)
    /// A mapping key appears twice — swift-yaml's `.reject` catches it (a doubled `state:` would
    /// otherwise silently last-win, a gate-field hazard). Carries the key + its 1-based position.
    case duplicateKey(key: String, line: Int, column: Int)
}

/// The `ConfigYAML` seam for evidence files (F29 · Path B, D6): split frontmatter/body, decode into the
/// typed record with **native duplicate-key rejection**, and validate; plus create-encode for a fresh
/// record. This is the sole target that touches `swift-yaml`; callers get pure `EDDCore.Evidence`
/// values. **Updating** an existing file is F30's job, via swift-yaml's `YAMLEditor.set`/`insert`
/// (byte-preserving in place) — this seam never re-serializes a file it read.
public enum EvidenceFrontmatter {

    /// Decode a friction/finding file (frontmatter + body) into a validated typed record. `filename`
    /// (when reading from disk) drives the `id`↔stem cross-check; `nil` for standalone text.
    public static func decode(_ text: String, filename: String? = nil) throws -> (evidence: any Evidence, body: String) {
        let (yaml, body) = try split(text)
        let evidence: any Evidence
        switch try schemaTag(of: yaml) {
        case FrictionEvent.schema: evidence = try decodeRecord(FrictionEvent.self, from: yaml)
        case Finding.schema:       evidence = try decodeRecord(Finding.self, from: yaml)
        case let other:            throw EvidenceError.unknownSchema(other)
        }
        try evidence.validate(filename: filename)
        return (evidence, body)
    }

    /// Encode a **freshly created** record (F30 `friction add`) to file text: field-declaration order,
    /// snake_case keys, **no `.sortedKeys`** (a fresh file carries only known fields, so the authored
    /// order stays readable — Path B). Existing-file updates go through `YAMLEditor`, not this.
    public static func encode(_ evidence: any Evidence, body: String) throws -> String {
        let yaml = try encodeRecord(evidence)
        let trimmed = yaml.hasSuffix("\n") ? String(yaml.dropLast()) : yaml
        let head = "---\n\(trimmed)\n---\n"
        // A well-formed text file ends with a newline (POSIX §3.206 — the final `\n` terminates the last
        // line; it also keeps Git from flagging "no newline at end of file", matching `RenderKit`). `head`
        // already ends in `\n`, so a body-less record needs nothing more.
        guard !body.isEmpty else { return head }
        return head + body + (body.hasSuffix("\n") ? "" : "\n")
    }

    // MARK: - internals

    private static func decoder() -> YAMLDecoder {
        let d = YAMLDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.duplicateKeyStrategy = .reject          // native strict duplicate rejection (swift-yaml #8)
        return d
    }

    /// The `schema:` tag (peeked before choosing the record). Runs the full `.reject` dup-scan, so a
    /// duplicate anywhere in the frontmatter fails here. Absent `schema` → `unknownSchema("<absent>")`.
    private static func schemaTag(of yaml: String) throws -> String {
        struct Peek: Decodable { var schema: String? }
        do {
            guard let s = try decoder().decode(Peek.self, from: yaml).schema else {
                throw EvidenceError.unknownSchema("<absent>")
            }
            return s
        } catch let e as EvidenceError { throw e } catch { throw mapDecodeError(error) }
    }

    private static func decodeRecord<R: Evidence>(_ type: R.Type, from yaml: String) throws -> R {
        do { return try decoder().decode(R.self, from: yaml) } catch { throw mapDecodeError(error) }
    }

    private static func encodeRecord(_ evidence: any Evidence) throws -> String {
        let e = YAMLEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        switch evidence {
        case let f as FrictionEvent: return try e.encode(f)
        case let f as Finding:       return try e.encode(f)
        default: throw ConfigError.malformedFrontmatter("unencodable evidence type")
        }
    }

    /// Split the leading `---\n … \n---\n` block via the shared ``FrontmatterSplit`` scan, mapped to this
    /// seam's `ConfigError` vocabulary. The single file-terminating newline is dropped from `body` (POSIX
    /// §3.206 — it terminates the last line, it isn't content), so `encode`'s trailing newline round-trips
    /// exactly: `decode(encode(x)).body == x.body`.
    private static func split(_ text: String) throws -> (yaml: String, body: String) {
        switch FrontmatterSplit.scan(text) {
        case .noOpening:
            throw ConfigError.malformedFrontmatter("missing opening `---`")
        case .unterminated:
            throw ConfigError.malformedFrontmatter("unterminated frontmatter")
        case let .split(yaml, body):
            guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConfigError.malformedFrontmatter("empty frontmatter")
            }
            let content = body.hasSuffix("\n") ? String(body.dropLast()) : body
            return (yaml, content)
        }
    }

    /// Map a `Codable`/`swift-yaml` decode failure to the right layer's error, splitting **structural
    /// (syntactic)** failures — which the seam owns (D4) — from **field-level (semantic)** ones, which
    /// belong to the pure core. This mirrors the standard structural-then-contextual validation layering
    /// (OWASP; HTTP parse-error vs. 422). Structural → `ConfigError.malformedFrontmatter`: a wrapped
    /// **non-duplicate** `YAMLError` (`.parse`/`.documentTooComplex` — the text isn't valid YAML), or an
    /// **empty coding path** (the frontmatter isn't a mapping at all). Semantic → the pure core: a missing
    /// required field → `missingField`, a specific field's bad value/type → `invalidValue`. (A duplicate
    /// key is its own `ConfigError`.)
    private static func mapDecodeError(_ error: Error) -> Error {
        guard let de = error as? DecodingError else { return ConfigError.malformedFrontmatter("\(error)") }
        // A missing key is always a missing *field* — the key names it — even at the root (semantic).
        if case let .keyNotFound(key, _) = de { return EvidenceError.missingField(key.stringValue) }
        let ctx = context(of: de)
        // A wrapped YAML error is a serialization failure: duplicateKey → its own case; parse/limit → structural.
        if let yaml = ctx.underlyingError as? YAMLError {
            if case let .duplicateKey(key, line, column) = yaml {
                return ConfigError.duplicateKey(key: key, line: line, column: column)
            }
            return ConfigError.malformedFrontmatter(yaml.description)
        }
        // An empty coding path = the whole frontmatter is the wrong shape (not a mapping) → structural.
        guard !ctx.codingPath.isEmpty else {
            return ConfigError.malformedFrontmatter(ctx.debugDescription)
        }
        // Otherwise a specific field carried a bad value / type → semantic (pure core). Name the **full**
        // path, not just the leaf: a bad `sessions` element is `sessions[0]`, not the bare index `0`
        // (RFC 9457 / JSON-Schema practice — locate the field, don't just report its type).
        return EvidenceError.invalidValue(field: fieldPath(ctx.codingPath), value: ctx.debugDescription)
    }

    /// A readable field name from a decode error's coding path: dotted keys, **bracketed indices** —
    /// `sessions[0]`, never the bare last component `0`. swift-yaml preserves the array index as the
    /// key's `intValue`, so an element error keeps its `sessions` context.
    private static func fieldPath(_ path: [any CodingKey]) -> String {
        path.reduce(into: "") { name, key in
            if let index = key.intValue { name += "[\(index)]" }
            else { name += name.isEmpty ? key.stringValue : ".\(key.stringValue)" }
        }
    }

    private static func context(of error: DecodingError) -> DecodingError.Context {
        switch error {
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c):
            return c
        @unknown default:
            return DecodingError.Context(codingPath: [], debugDescription: "\(error)")
        }
    }
}
