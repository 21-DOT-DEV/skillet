import Foundation

/// A frozen, single-shape boundary document held as its **raw JSON object** so the codec round-trips
/// faithfully and preserves unmodeled keys (the tolerant-reader / wire-compatibility discipline, F8).
/// Conformers add typed accessors over `fields` for the field-exact keys the viewer/tooling depend on;
/// they never rewrite or drop anything on re-emit. (`evals.json` is *not* a conformer — it has two
/// container shapes; see ``EvalsFile``.)
public protocol RawJSONObject: Codable, Sendable, Equatable {
    var fields: [String: JSONValue] { get set }
    init(fields: [String: JSONValue])
}

// These extension witnesses are what make a conformer round-trip **raw**. By satisfying `Codable`'s
// requirements here they *suppress* per-conformer synthesis — which would instead emit `{"fields":{…}}`
// (the storage name leaked onto the wire), the exact opposite of the verbatim re-emit we need.
//
// INVARIANT: a conformer must have **exactly one stored property, `fields`**. These witnesses only
// read/write `fields`, so any *second* stored property would be silently dropped on the wire (no compile
// error) and could also change how synthesis resolves — put derived data in computed accessors instead.
// Guard: the round-trip tests in `RunRecordsTests` fail loudly if a conformer ever stops re-emitting its
// document verbatim.
public extension RawJSONObject {
    init(from decoder: Decoder) throws {
        guard let object = try JSONValue(from: decoder).objectValue else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "expected a JSON object"))
        }
        self.init(fields: object)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue.object(fields))
    }

    /// A modeled top-level value by its exact wire key.
    subscript(_ key: String) -> JSONValue? { fields[key] }
}
