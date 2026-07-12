import EDDCore

/// The result of a sanitize pass: the scrubbed artifacts + a report. Only the report's **summary** —
/// `{scanner, version?, redactions?}` — is serialized into the frozen `session-meta.sanitization`
/// (R5: no `disabled` field — capture never writes an un-scrubbed bundle). Per-rule/per-artifact detail,
/// if a scanner produces it, stays in-memory for the human-facing printout.
public struct SanitizationReport: Sendable, Equatable {
    public let scanner: String
    public let version: String?
    public let redactions: Int?

    public init(scanner: String, version: String? = nil, redactions: Int? = nil) {
        self.scanner = scanner
        self.version = version
        self.redactions = redactions
    }

    /// The frozen `session-meta.sanitization` object (sorted-key/pretty is the writer's concern).
    public var summary: [String: JSONValue] {
        var s: [String: JSONValue] = ["scanner": .string(scanner)]
        if let version { s["version"] = .string(version) }
        if let redactions { s["redactions"] = .number(Double(redactions)) }
        return s
    }
}

/// The scrub seam — **async** because its real conformer shells a subprocess. The capture command runs
/// it on the assembled ``BundleText`` **before scoring**, then hands the redacted artifacts + report to
/// the writer (which *requires* the report — the enforced-path guard). The production
/// `BetterleaksSanitizer` lives in `SanitizerKit` (F32).
public protocol Sanitizer: Sendable {
    func sanitize(_ artifacts: BundleText) async throws -> (redacted: BundleText, report: SanitizationReport)
}

/// A pass-through sanitizer — **test double only, never a production default** (R5: the constitution
/// forbids writing an un-scrubbed bundle; capture is exposure-gated on a *real* scanner being wired).
/// Used to exercise the writer/pipeline without a live scanner.
public struct NoopSanitizer: Sanitizer {
    public init() {}
    public func sanitize(_ artifacts: BundleText) async throws -> (redacted: BundleText, report: SanitizationReport) {
        (artifacts, SanitizationReport(scanner: "none"))
    }
}
