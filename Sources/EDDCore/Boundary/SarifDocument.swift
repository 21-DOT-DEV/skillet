import Foundation

/// A discrete SARIF severity (`result.level`). Distinct from the continuous ``SarifResult/rank``:
/// `level` buckets, `rank` (0–100) carries the fine-grained score. `none` is emitted for a pass-like
/// result; the scorers use `note`/`warning`/`error` only.
public enum SarifLevel: String, Codable, Sendable, Equatable, CaseIterable {
    case none, note, warning, error
}

/// A **typed, emit-only** SARIF 2.1.0 log (F17). Companion to the tolerant reader ``SarifLog`` — this
/// is the *writer*: skillet authors the shape, so there is no unknown-key round-tripping to preserve.
/// Serialized by ``jsonString()`` with a **camelCase** encoder (the shared `SkilletJSON` is snake_case,
/// which would emit `start_line`/`rule_id` and break GitHub/SonarQube ingestion). Frozen boundary
/// format — golden-tested.
public struct SarifDocument: Encodable, Sendable, Equatable {
    /// The advisory schema pointer. The community mirror (what the repo's reader tests already use);
    /// the OASIS canonical is the authoritative source:
    /// `https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json`.
    public static let schemaURI = "https://json.schemastore.org/sarif-2.1.0.json"
    public static let version = "2.1.0"

    public let runs: [SarifRun]
    public init(runs: [SarifRun]) { self.runs = runs }

    private enum CodingKeys: String, CodingKey { case schema = "$schema"; case version; case runs }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaURI, forKey: .schema)
        try c.encode(Self.version, forKey: .version)
        try c.encode(runs, forKey: .runs)
    }

    /// Serialize to camelCase SARIF 2.1.0 JSON (no trailing newline). Deterministic (`sortedKeys`), and
    /// **not** via `SkilletJSON` — the default key strategy keeps `startLine`/`ruleId`/`$schema` literal.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

public struct SarifRun: Encodable, Sendable, Equatable {
    public let tool: SarifTool
    public let results: [SarifResult]
    public init(tool: SarifTool, results: [SarifResult]) { self.tool = tool; self.results = results }
}

public struct SarifTool: Encodable, Sendable, Equatable {
    public let driver: SarifDriver
    public init(driver: SarifDriver) { self.driver = driver }
}

/// The tool descriptor. `rules` is a **static catalog** — every rule the tool can emit, listed whether
/// or not it fired this run (the SARIF-idiomatic "advertise your catalog" model).
public struct SarifDriver: Encodable, Sendable, Equatable {
    public let name: String
    public let version: String
    public let rules: [SarifRule]
    public init(name: String, version: String, rules: [SarifRule]) {
        self.name = name; self.version = version; self.rules = rules
    }
}

public struct SarifRule: Encodable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let shortDescription: SarifMessage
    public let properties: [String: JSONValue]?
    public init(id: String, name: String, shortDescription: String, properties: [String: JSONValue]? = nil) {
        self.id = id; self.name = name; self.shortDescription = SarifMessage(text: shortDescription)
        self.properties = (properties?.isEmpty ?? true) ? nil : properties
    }
}

public struct SarifResult: Encodable, Sendable, Equatable {
    public let ruleId: String
    public let level: SarifLevel
    public let rank: Double?
    public let message: SarifMessage
    public let locations: [SarifLocation]
    public let properties: [String: JSONValue]?

    public init(ruleId: String, level: SarifLevel, rank: Double?, message: String,
                locations: [SarifLocation], properties: [String: JSONValue]?) {
        self.ruleId = ruleId; self.level = level; self.rank = rank
        self.message = SarifMessage(text: message); self.locations = locations
        self.properties = (properties?.isEmpty ?? true) ? nil : properties
    }
}

public struct SarifMessage: Encodable, Sendable, Equatable {
    public let text: String
    public init(text: String) { self.text = text }
}

public struct SarifLocation: Encodable, Sendable, Equatable {
    public let physicalLocation: SarifPhysicalLocation
    public init(physicalLocation: SarifPhysicalLocation) { self.physicalLocation = physicalLocation }
    /// A file-level location (categorical rules): `artifactLocation` only, no `region`.
    public static func file(_ uri: String) -> SarifLocation {
        SarifLocation(physicalLocation: SarifPhysicalLocation(artifactLocation: SarifArtifactLocation(uri: uri), region: nil))
    }
}

public struct SarifPhysicalLocation: Encodable, Sendable, Equatable {
    public let artifactLocation: SarifArtifactLocation
    public let region: SarifRegion?
    public init(artifactLocation: SarifArtifactLocation, region: SarifRegion?) {
        self.artifactLocation = artifactLocation; self.region = region
    }
}

public struct SarifArtifactLocation: Encodable, Sendable, Equatable {
    public let uri: String
    public init(uri: String) { self.uri = uri }
}

/// A region within an artifact. Line/column are **1-based**; `charOffset`/`charLength` are **0-based**,
/// per the SARIF spec. All counts are **Unicode scalars** (§4.3). `endColumn` is the column immediately
/// after the region.
public struct SarifRegion: Encodable, Sendable, Equatable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int
    public let charOffset: Int
    public let charLength: Int
    public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int, charOffset: Int, charLength: Int) {
        self.startLine = startLine; self.startColumn = startColumn
        self.endLine = endLine; self.endColumn = endColumn
        self.charOffset = charOffset; self.charLength = charLength
    }
}
