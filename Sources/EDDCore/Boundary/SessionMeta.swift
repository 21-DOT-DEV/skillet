import Foundation

/// Per-session identity record — `<date>-<slug>.session-meta.json` in a bundle (design §7.2). A
/// **frozen boundary** format: held as a ``RawJSONObject`` so hand-added keys round-trip and F32's
/// `sanitization` fields stay additive (a plain `Codable` struct would silently drop unknown keys,
/// violating the append-only policy). Keys are snake_case; the writer emits sorted + pretty to match
/// the existing corpus byte-shape.
///
/// Modeled keys: `id`, `skill`, `skill_version`, `model`, `harness` (a **plain string** — the codec is
/// in `EDDCore`, below `TraceKit`, so it can't see `HarnessID`; the command stringifies it),
/// `captured_at`, `schema_version` (2 since F26 — it carries `sanitization`), and the optional
/// `sanitization` object `{scanner, version?, redactions?}`. `"unknown"` is the defined sentinel for an
/// unresolved `model`/`skill_version` (counted separately in diversity readings, never poisons them).
public struct SessionMeta: RawJSONObject {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    public static let unknownValue = "unknown"
    public static let currentSchemaVersion = 2

    // MARK: Typed accessors (exact wire keys)
    public var id: String? { fields["id"]?.stringValue }
    public var skill: String? { fields["skill"]?.stringValue }
    public var skillVersion: String? { fields["skill_version"]?.stringValue }
    public var model: String? { fields["model"]?.stringValue }
    public var harness: String? { fields["harness"]?.stringValue }
    public var capturedAt: String? { fields["captured_at"]?.stringValue }
    public var schemaVersion: Int? { fields["schema_version"]?.numberValue.map(Int.init) }
    /// The `sanitization` summary object, if present: `{scanner, version?, redactions?}`.
    public var sanitization: [String: JSONValue]? { fields["sanitization"]?.objectValue }

    /// Build the modeled record. `sanitization` is optional (absent in the pre-F26 corpus).
    public init(
        id: String, skill: String, skillVersion: String, model: String, harness: String,
        capturedAt: String, schemaVersion: Int = SessionMeta.currentSchemaVersion,
        sanitization: [String: JSONValue]? = nil
    ) {
        var f: [String: JSONValue] = [
            "id": .string(id),
            "skill": .string(skill),
            "skill_version": .string(skillVersion),
            "model": .string(model),
            "harness": .string(harness),
            "captured_at": .string(capturedAt),
            "schema_version": .number(Double(schemaVersion)),
        ]
        if let sanitization { f["sanitization"] = .object(sanitization) }
        self.init(fields: f)
    }

    /// Fill `"unknown"` for an unresolved `model`/`skill_version` (the command applies flag/JSONL/env
    /// precedence and passes the winner or `nil`).
    public static func resolve(
        id: String, skill: String, harness: String,
        model: String?, skillVersion: String?, capturedAt: String,
        sanitization: [String: JSONValue]? = nil
    ) -> SessionMeta {
        SessionMeta(
            id: id, skill: skill,
            skillVersion: skillVersion ?? unknownValue,
            model: model ?? unknownValue,
            harness: harness, capturedAt: capturedAt, sanitization: sanitization)
    }

    public static func isUnknown(_ value: String?) -> Bool { value == unknownValue }
}
