import Foundation

/// A SARIF 2.1.0 log, held **raw** for faithful, unknown-preserving round-trips. skillet emits a subset
/// (the scorers' findings, Phase 2) and reads SARIF from session bundles. Holding it raw means unknown
/// properties *and* unrecognized enum values (e.g. a future `level`) are preserved rather than
/// rejected — there is no closed Swift enum to hard-fail on, which is exactly the tolerant-reader
/// posture F8 wants. Per the SARIF spec, non-standard data belongs in each object's `properties` bag.
public struct SarifLog: RawJSONObject {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }

    public var version: String? { fields["version"]?.stringValue }
    public var schemaURI: String? { fields["$schema"]?.stringValue }
    public var runs: [JSONValue] { fields["runs"]?.arrayValue ?? [] }
}

/// The role a captured SARIF file plays in the A/B audit (design §9.4) — carried in the file *name*
/// (`<slug>.audit-baseline.sarif` / `<slug>.audit-input.sarif`), not the SARIF body. `bundle verify`'s
/// directionality check (Phase 3) consumes this.
public enum SarifRole: String, Sendable, Equatable, CaseIterable {
    /// A producer skill's emitted findings (the baseline it generates).
    case auditBaseline = "audit-baseline"
    /// A consumer-side scan's input findings.
    case auditInput = "audit-input"

    /// Derive the role from a SARIF filename, if it carries one of the role suffixes.
    public init?(filename: String) {
        for role in SarifRole.allCases where filename.hasSuffix(".\(role.rawValue).sarif") {
            self = role
            return
        }
        return nil
    }
}
