import Foundation

/// The skill-creator 2.0 **run-record family** (grounded against `references/schemas.md` + real
/// `~/Developer/skills` artifacts, 2026-06-24). Each is a frozen boundary format skillet's runner
/// (F7) produces and the eval-viewer consumes; field names are viewer-exact, so these stay raw and
/// round-trip faithfully (unknown keys preserved). Accessors expose the load-bearing keys only.

/// `benchmark.json` — `{metadata, runs:[{configuration, result}], run_summary, notes?}`.
public struct BenchmarkFile: RawJSONObject {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    public var metadata: [String: JSONValue]? { fields["metadata"]?.objectValue }
    public var skillName: String? { metadata?["skill_name"]?.stringValue }
    public var runs: [JSONValue] { fields["runs"]?.arrayValue ?? [] }
    public var runSummary: [String: JSONValue]? { fields["run_summary"]?.objectValue }
    public var notes: [String]? { fields["notes"]?.stringArray }
}

/// `grading.json` — `{expectations:[{text, passed, evidence}], summary:{passed, failed, total, pass_rate}, …}`.
/// The `text`/`passed`/`evidence` field names are viewer-hardcoded (deep-research-confirmed).
public struct GradingFile: RawJSONObject {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    public var expectations: [JSONValue] { fields["expectations"]?.arrayValue ?? [] }
    public var summary: [String: JSONValue]? { fields["summary"]?.objectValue }
    public var passRate: Double? { summary?["pass_rate"]?.numberValue }
    public var passed: Int? { summary?["passed"]?.numberValue.map(Int.init) }
    public var total: Int? { summary?["total"]?.numberValue.map(Int.init) }
}

/// `timing.json` — `{total_tokens, duration_ms, total_duration_seconds, …}`.
public struct TimingFile: RawJSONObject {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    public var totalTokens: Int? { fields["total_tokens"]?.numberValue.map(Int.init) }
    public var durationMs: Int? { fields["duration_ms"]?.numberValue.map(Int.init) }
}

/// `metrics.json` — `{tool_calls:{name:count}, total_tool_calls, total_steps, files_created, errors_encountered, …}`.
public struct MetricsFile: RawJSONObject {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    public var toolCalls: [String: JSONValue]? { fields["tool_calls"]?.objectValue }
    public var totalSteps: Int? { fields["total_steps"]?.numberValue.map(Int.init) }
    public var filesCreated: [String]? { fields["files_created"]?.stringArray }
}

/// `eval_metadata.json` — per-test `{name, assertions[]}` (skill-creator workflow).
public struct EvalMetadataFile: RawJSONObject {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    public var name: String? { fields["name"]?.stringValue }
    public var assertions: [String] { fields["assertions"]?.stringArray ?? [] }
}
