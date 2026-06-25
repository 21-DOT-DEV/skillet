import Foundation

/// An opaque, recursive JSON value — the carrier that lets the frozen boundary-format codecs (F8) hold a
/// document **raw** and re-emit it **verbatim**, so unmodeled keys round-trip by construction. (Swift's
/// synthesized `Codable` instead *drops* unknown keys on decode — deep-research-confirmed, Swift Forums
/// #63445 — which is why every boundary codec holds its raw `JSONValue`/`[String: JSONValue]` rather than
/// mapping to typed stored fields.) This "hold the raw, re-emit verbatim" is the single round-trip idiom.
///
/// Numbers are held as `Double`: every numeric field in the eval/benchmark formats (ids, counts,
/// `pass_rate`, token totals) fits exactly under 2^53, and Foundation's `JSONEncoder` re-emits an
/// integral `Double` without a decimal point (`3`, not `3.0`) — locked by an explicit byte test, since
/// the D5 promise is byte-ish compatibility with the skill-creator viewer. **Fidelity bound:** this caps
/// faithful round-tripping at 2^53 *including for preserved-unknown keys* — an integer above 2^53 in any
/// field (modeled or unknown) round-trips lossily and silently. No boundary format defines such a field
/// today; revisit (e.g. a raw-number-token case) if one ever appears. Equality is **semantic**
/// (`1 == 1.0`, order-independent objects), which is what golden comparison should use — byte comparison
/// of re-encoded JSON is unsafe because `JSONEncoder.sortedKeys` is not stable across Darwin/Linux
/// (deep-research-confirmed, swift-corelibs-foundation #4702).
public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "value is not representable as JSON")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n): try c.encode(n)
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }
}

// MARK: - Convenience accessors

public extension JSONValue {
    var stringValue: String? { if case let .string(s) = self { return s } else { return nil } }
    var numberValue: Double? { if case let .number(n) = self { return n } else { return nil } }
    var boolValue: Bool? { if case let .bool(b) = self { return b } else { return nil } }
    var arrayValue: [JSONValue]? { if case let .array(a) = self { return a } else { return nil } }
    var objectValue: [String: JSONValue]? { if case let .object(o) = self { return o } else { return nil } }
    /// The string elements of an array value (non-strings dropped); `nil` if not an array.
    var stringArray: [String]? { arrayValue?.compactMap(\.stringValue) }
}

// MARK: - Golden comparison

/// Semantic JSON equality for golden tests — order-independent and `1 == 1.0`. Byte comparison of
/// encoder output is **not** a safe golden because `sortedKeys` differs across Darwin/Linux (F8 research).
public func jsonSemanticEqual(_ a: Data, _ b: Data) throws -> Bool {
    let decoder = JSONDecoder()
    return try decoder.decode(JSONValue.self, from: a) == decoder.decode(JSONValue.self, from: b)
}

/// Semantic JSON equality for golden tests, from strings.
public func jsonSemanticEqual(_ a: String, _ b: String) throws -> Bool {
    try jsonSemanticEqual(Data(a.utf8), Data(b.utf8))
}
