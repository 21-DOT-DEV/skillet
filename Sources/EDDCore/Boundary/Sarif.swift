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

    // MARK: Read accessors (F33 triage)

    /// The first run's `tool.driver.version` — the scorer version recorded at capture time, which
    /// triage compares against the running version for its staleness note (Specs/016 D1). Tolerant
    /// raw traversal (this type's whole posture): any missing link yields `nil`, never a throw.
    public var toolVersion: String? {
        runs.first?.objectValue?["tool"]?.objectValue?["driver"]?.objectValue?["version"]?.stringValue
    }

    /// Every run's `results[]`, sliced to the fields triage clusters on. Tolerant: a result missing a
    /// field slices to `nil`s (the consumer decides how to disclose it); a foreign tool's bare-string
    /// `message` (nonstandard but seen in the wild) is accepted alongside the spec's `{text:}` object.
    public var resultSlices: [SarifResultSlice] {
        runs.flatMap { run -> [SarifResultSlice] in
            (run.objectValue?["results"]?.arrayValue ?? []).map { result in
                let object = result.objectValue
                let message = object?["message"]?.objectValue?["text"]?.stringValue
                    ?? object?["message"]?.stringValue
                return SarifResultSlice(
                    ruleId: object?["ruleId"]?.stringValue,
                    level: object?["level"]?.stringValue,
                    message: message)
            }
        }
    }
}

/// One SARIF result reduced to the triage-relevant fields (F33). `level` stays a raw string — an
/// unrecognized future level survives to the report rather than hard-failing an enum (tolerant reader).
public struct SarifResultSlice: Sendable, Equatable {
    public let ruleId: String?
    public let level: String?
    public let message: String?
    public init(ruleId: String?, level: String?, message: String?) {
        self.ruleId = ruleId; self.level = level; self.message = message
    }
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
