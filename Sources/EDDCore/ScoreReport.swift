import Foundation

/// The `skillet.score/1` machine payload (`skillet score --format json`) — the house `--json` surface
/// (design §5.5), emitted via ``SkilletJSON`` (snake_case, schema-stamped). Distinct from the camelCase
/// ``SarifDocument`` (F17 emits both): SARIF's casing is spec-mandated, this one is house-consistent.
public struct ScoreReport: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.score/1"
    public let findings: [ScoreFinding]
    public let summary: ScoreSummary
    public init(findings: [ScoreFinding], summary: ScoreSummary) {
        self.findings = findings; self.summary = summary
    }
}

public struct ScoreFinding: Codable, Sendable, Equatable {
    public let ruleId: String            // → rule_id
    public let level: SarifLevel
    public let rank: Double?
    public let message: String
    public let location: ScoreLocation
    public let properties: [String: JSONValue]?
    public init(ruleId: String, level: SarifLevel, rank: Double?, message: String,
                location: ScoreLocation, properties: [String: JSONValue]?) {
        self.ruleId = ruleId; self.level = level; self.rank = rank
        self.message = message; self.location = location
        self.properties = (properties?.isEmpty ?? true) ? nil : properties
    }
}

public struct ScoreSummary: Codable, Sendable, Equatable {
    public let perRule: [String: Int]    // → per_rule (object keyed by rule id, not an array)
    public let filesScored: Int
    public let filesSkipped: Int
    public let filesUnreadable: Int
    public init(perRule: [String: Int], filesScored: Int, filesSkipped: Int, filesUnreadable: Int) {
        self.perRule = perRule; self.filesScored = filesScored
        self.filesSkipped = filesSkipped; self.filesUnreadable = filesUnreadable
    }
}

/// A finding's location — a **sum type** the encoder flattens into one object, so a categorical finding
/// cannot carry region fields (the type enforces the SARIF "artifactLocation with no region" rule). A
/// Swift enum does not synthesize to the flat object the `skillet.score/1` schema documents, so the
/// `Codable` is hand-written: `file` is always present; the region fields appear only for `.region`.
/// The `SkilletJSON` key strategy still snake_cases the camelCase `CodingKeys` (`start_line`, …).
public enum ScoreLocation: Codable, Sendable, Equatable {
    case file(String)                                                                              // S000/S007
    case region(file: String, startLine: Int, startColumn: Int, endLine: Int, endColumn: Int, charOffset: Int, charLength: Int)  // S001–S006

    private enum CodingKeys: String, CodingKey {
        case file, startLine, startColumn, endLine, endColumn, charOffset, charLength
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(f):
            try c.encode(f, forKey: .file)
        case let .region(f, sl, sc, el, ec, co, cl):
            try c.encode(f, forKey: .file)
            try c.encode(sl, forKey: .startLine)
            try c.encode(sc, forKey: .startColumn)
            try c.encode(el, forKey: .endLine)
            try c.encode(ec, forKey: .endColumn)
            try c.encode(co, forKey: .charOffset)
            try c.encode(cl, forKey: .charLength)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let f = try c.decode(String.self, forKey: .file)
        if let sl = try c.decodeIfPresent(Int.self, forKey: .startLine) {
            self = .region(file: f, startLine: sl,
                           startColumn: try c.decode(Int.self, forKey: .startColumn),
                           endLine: try c.decode(Int.self, forKey: .endLine),
                           endColumn: try c.decode(Int.self, forKey: .endColumn),
                           charOffset: try c.decode(Int.self, forKey: .charOffset),
                           charLength: try c.decode(Int.self, forKey: .charLength))
        } else {
            self = .file(f)
        }
    }
}
