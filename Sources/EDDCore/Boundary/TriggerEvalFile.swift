import Foundation

/// The frozen `trigger-eval.json` boundary format (skillet's trigger axis, design §7.2): a bare array
/// of `{query, should_trigger}` pairs. Held **raw** (like ``EvalsFile``) so the document round-trips
/// verbatim — unknown keys *and* any non-object array elements are preserved, not silently dropped.
/// The counts support a later `SKILL-L010` (≥3 should-trigger **and** ≥3 should-not).
public struct TriggerEvalFile: Codable, Sendable, Equatable {
    /// The raw JSON array, re-emitted verbatim.
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard value.arrayValue != nil else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "trigger-eval.json must be a JSON array of {query, should_trigger}"))
        }
        raw = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    /// The object elements as cases. Non-object array elements are preserved in `raw` (so the
    /// round-trip stays faithful) but are not surfaced as cases.
    public var cases: [TriggerCase] {
        (raw.arrayValue ?? []).compactMap { $0.objectValue.map(TriggerCase.init(fields:)) }
    }
    public var caseCount: Int { cases.count }
    public var shouldTriggerCount: Int { cases.filter { $0.shouldTrigger == true }.count }
    public var shouldNotTriggerCount: Int { cases.filter { $0.shouldTrigger == false }.count }
}

public struct TriggerCase: Sendable, Equatable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    public var query: String? { fields["query"]?.stringValue }
    public var shouldTrigger: Bool? { fields["should_trigger"]?.boolValue }
}
