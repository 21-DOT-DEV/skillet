/// The severity of a lint ``Diagnostic`` (design §6.1). `error` fails the gate (exit 1); `warn` is
/// advisory (exit 0).
public enum DiagnosticTier: String, Codable, Sendable, Equatable {
    case error
    case warn
}

/// One lint finding: a stable rule id, its tier, the skill it concerns, a human message, and the
/// exact fixing action (Appendix B's "what / why / fix"). `location` is reserved for a future
/// line/column anchor (F3 / SARIF); F4 leaves it `nil`. The id space (`SKILL-Lxxx`) is additive
/// within the major, so new rules slot in without a schema bump.
public struct Diagnostic: Codable, Sendable, Equatable {
    public let id: String
    public let tier: DiagnosticTier
    public let skill: String
    public let message: String
    public let fixHint: String
    public let location: String?

    public init(
        id: String,
        tier: DiagnosticTier,
        skill: String,
        message: String,
        fixHint: String,
        location: String? = nil
    ) {
        self.id = id
        self.tier = tier
        self.skill = skill
        self.message = message
        self.fixHint = fixHint
        self.location = location
    }
}

/// The `--json` payload for `skillet lint` (`skillet.lint/1`): every diagnostic plus error/warn
/// tallies so scripts can branch on the gate without re-counting. Additive within the major — new
/// rules and fields slot in without a bump.
public struct LintReport: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.lint/1"
    public let diagnostics: [Diagnostic]
    public let errors: Int
    public let warnings: Int

    public init(diagnostics: [Diagnostic]) {
        self.diagnostics = diagnostics
        self.errors = diagnostics.lazy.filter { $0.tier == .error }.count
        self.warnings = diagnostics.lazy.filter { $0.tier == .warn }.count
    }
}
