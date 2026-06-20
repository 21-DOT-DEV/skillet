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
}
