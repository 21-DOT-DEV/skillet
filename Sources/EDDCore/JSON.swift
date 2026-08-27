import Foundation

/// A machine payload that declares its versioned schema id (design §5.5). Every `--json` payload is
/// emitted inside an ``Envelope`` that stamps this `schema` field, e.g. `"skillet.root/1"`.
public protocol SchemaIdentified: Encodable {
    /// The payload's schema id, of the form `skillet.<thing>/<major>`.
    static var schema: String { get }
}

/// A `CodingKey` built from an arbitrary string, used to inject the `schema` field at the top level.
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Wraps a ``SchemaIdentified`` payload and encodes a flat object whose first-class `schema` field
/// sits alongside the payload's own fields (matching the design's `{ "schema": …, … }` shape).
public struct Envelope<Payload: SchemaIdentified>: Encodable {
    public let payload: Payload
    public init(_ payload: Payload) { self.payload = payload }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(Payload.schema, forKey: DynamicCodingKey("schema"))
        // Merge the payload's own keyed fields into the same top-level container.
        try payload.encode(to: encoder)
    }
}

/// Centralized, deterministic JSON encoding for every `--json` payload: sorted keys + snake_case +
/// ISO-8601 UTC dates, so output is byte-stable and golden-testable (constitution III).
public enum SkilletJSON {
    /// The shared encoder. Deterministic output: identical inputs always produce identical bytes.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Encode a payload as a schema-stamped JSON string (no trailing newline).
    public static func encode<Payload: SchemaIdentified>(_ payload: Payload) throws -> String {
        let data = try encoder().encode(Envelope(payload))
        return String(decoding: data, as: UTF8.self)
    }

    /// The shared decoder, mirroring ``encoder()`` (snake_case keys, ISO-8601 UTC dates). The
    /// envelope's injected `schema` key is simply ignored on read; *schema-validating* decode (for
    /// the frozen boundary formats) lands with F8.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            DynamicCodingKey(Self.swiftName(forPublishedKey: path[path.count - 1].stringValue))
        }
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// **A published key, turned back into the name the type spells it with.**
    ///
    /// Written out because the built-in conversion cannot express one thing this format needs. Two of the
    /// published names carry a digit as a word — `pass_1`, `pass_1_evals` — and the built-in rule turns
    /// those into `pass1` and `pass1Evals`, which match nothing, so the whole payload failed to read back.
    /// Measured: encoding produced the right text and decoding it returned nothing at all.
    ///
    /// So a name whose parts include a bare number is handed back exactly as written, and everything else
    /// gets the ordinary treatment. The written-out rule below is checked against the built-in one for
    /// every key this project publishes, so "the ordinary treatment" cannot quietly drift from what the
    /// encoder does.
    static func swiftName(forPublishedKey key: String) -> String {
        let parts = key.split(separator: "_", omittingEmptySubsequences: false)
        // A part that is only digits is a word here, not a separator artefact; such names are published
        // exactly as spelled and must be read back the same way.
        guard !parts.contains(where: { !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return key }
        // Leading and trailing underscores are preserved by the built-in rule; keep them.
        let leading = String(repeating: "_", count: key.prefix(while: { $0 == "_" }).count)
        let trailing = String(repeating: "_", count: key.reversed().prefix(while: { $0 == "_" }).count)
        let words = parts.filter { !$0.isEmpty }
        guard let first = words.first else { return key }
        let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return leading + first.lowercased() + rest.joined() + (key == leading ? "" : trailing)
    }

    /// Decode a value from a JSON string using the shared decoder.
    public static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder().decode(type, from: Data(json.utf8))
    }
}
