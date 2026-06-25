import Foundation

/// The frozen `trigger-eval.json` boundary format (skillet's trigger axis, design §7.2): a bare array
/// of `{query, should_trigger}` pairs. Cases are kept raw for faithful, unknown-preserving round-trips;
/// the counts support F-later's `SKILL-L010` (≥3 should-trigger **and** ≥3 should-not).
public struct TriggerEvalFile: Codable, Sendable, Equatable {
    public var cases: [TriggerCase]
    public init(cases: [TriggerCase]) { self.cases = cases }

    public var caseCount: Int { cases.count }
    public var shouldTriggerCount: Int { cases.filter { $0.shouldTrigger == true }.count }
    public var shouldNotTriggerCount: Int { cases.filter { $0.shouldTrigger == false }.count }

    public init(from decoder: Decoder) throws {
        guard let items = try JSONValue(from: decoder).arrayValue else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "trigger-eval.json must be a JSON array of {query, should_trigger}"))
        }
        cases = items.compactMap { $0.objectValue.map(TriggerCase.init(fields:)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(JSONValue.array(cases.map { .object($0.fields) }))
    }
}

public struct TriggerCase: Sendable, Equatable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    public var query: String? { fields["query"]?.stringValue }
    public var shouldTrigger: Bool? { fields["should_trigger"]?.boolValue }
}
