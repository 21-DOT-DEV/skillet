import Foundation

/// The frozen `evals.json` boundary format — a skill's behavioral eval cases. skillet reads two shapes
/// (deep-research + real-artifact grounding, 2026-06-24):
///   - skill-creator 2.0 (canonical): `{ "skill_name": …, "evals": [ {id, prompt, expected_output, files?, expectations} ] }`
///   - legacy bare array:             `[ {skills, query, files?, expected_behavior, timeout_seconds?} ]`
///
/// The whole document is held **raw** (`JSONValue`) and re-emitted **verbatim**, so the codec round-trips
/// with perfect fidelity — no key rename, no injected fields, unknown keys preserved. `EvalCase`'s
/// accessors normalize the field aliases (`query`→prompt, `assertions`/`expected_behavior`→expectations)
/// for skillet's own use *without* touching the wire. `caseCount` drives F4's `SKILL-L009`.
///
/// (`cases` is **not** accepted as a container key: it is not in skill-creator 2.0 nor in any real
/// sampled file — only `evals`. Re-introduce it only if a real file is found, with a test.)
public struct EvalsFile: Codable, Sendable, Equatable {
    /// The raw decoded JSON document — object for 2.0, array for legacy — preserved verbatim.
    public var raw: JSONValue

    public init(raw: JSONValue) { self.raw = raw }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard value.objectValue != nil || value.arrayValue != nil else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "evals.json must be a JSON array (legacy) or object (skill-creator 2.0)"))
        }
        raw = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)   // verbatim — perfectly faithful round-trip
    }

    /// True when the source is a legacy bare array (vs. the 2.0 object).
    public var isLegacyArray: Bool { raw.arrayValue != nil }

    /// The `skill_name` (2.0 object form); `nil` for the legacy array.
    public var skillName: String? { raw.objectValue?["skill_name"]?.stringValue }

    /// The eval cases — the legacy array's elements, or the 2.0 object's `evals`.
    public var cases: [EvalCase] {
        let list = raw.arrayValue ?? raw.objectValue?["evals"]?.arrayValue ?? []
        return list.compactMap { $0.objectValue.map(EvalCase.init(fields:)) }
    }

    /// Unmodeled top-level keys (object form) for inspection; preserved on re-emit regardless.
    public var extra: [String: JSONValue] {
        guard var obj = raw.objectValue else { return [:] }
        obj["skill_name"] = nil
        obj["evals"] = nil
        return obj
    }

    /// Case count — drives `SKILL-L009`.
    public var caseCount: Int { cases.count }
}

/// One eval case, kept as its raw JSON object for faithful round-tripping; accessors normalize the
/// 2.0 / legacy / local field aliases for skillet's use.
public struct EvalCase: Sendable, Equatable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    /// The case id — 2.0 `id`, if present (the runner falls back to a positional id otherwise).
    /// skill-creator 2.0 ids are commonly **numeric**, so a JSON number is coerced to its string form
    /// (`0`, not `0.0`) rather than dropped — otherwise records would lose the source eval id.
    public var id: String? {
        if let string = fields["id"]?.stringValue { return string }
        if let number = fields["id"]?.numberValue { return Int(exactly: number).map(String.init) ?? String(number) }
        return nil
    }
    /// The task prompt — 2.0 `prompt`, else legacy `query`.
    public var prompt: String? { fields["prompt"]?.stringValue ?? fields["query"]?.stringValue }
    /// The assertions/criteria — 2.0 `expectations`, else local `assertions`, else legacy `expected_behavior`.
    public var expectations: [String] {
        (fields["expectations"] ?? fields["assertions"] ?? fields["expected_behavior"])?.stringArray ?? []
    }
    /// The 2.0 reference output, if present.
    public var expectedOutput: String? { fields["expected_output"]?.stringValue }
    /// Staged input files for the trial.
    public var files: [String] { fields["files"]?.stringArray ?? [] }
}
