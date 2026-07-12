import CorpusKit

/// The production `Sanitizer` (F32): scans every bundle artifact with `betterleaks`, drops findings on
/// exempt paths, and value-redacts the survivors across **all** artifacts + the structured trace.
///
/// Pipeline (§3.1): gather `BundleText.scanInputs` (each artifact labeled with its path) → scan per
/// artifact via the injected `SecretScanner` → **drop findings whose `File` is in `exemptPaths`**
/// (post-scan false-positive filter, R6-2) → span-merge redact every occurrence of every surviving
/// secret. Because redaction is **value-based**, a secret found in one artifact is scrubbed everywhere
/// (transcript, diff, bodies, and trace tool-arguments).
public struct BetterleaksSanitizer: Sanitizer {
    let scanner: any SecretScanner
    /// Bundle-relative paths whose findings are treated as false positives (`sanitize.exempt_paths`).
    let exemptPaths: Set<String>
    /// The resolved scanner version, recorded in provenance (nil if not probed).
    let version: String?

    public init(scanner: any SecretScanner, exemptPaths: Set<String> = [], version: String? = nil) {
        self.scanner = scanner
        self.exemptPaths = exemptPaths
        self.version = version
    }

    public func sanitize(_ artifacts: BundleText) async throws -> (redacted: BundleText, report: SanitizationReport) {
        // Fail closed on a blanket exempt pattern (`**`, `*`, …): it would drop every finding and write an
        // unredacted bundle — the `--no-sanitize` equivalent the constitution forbids (R5). Checked before
        // scanning, so nothing is ever redacted-then-exempted-wholesale.
        if let broad = exemptPaths.first(where: ExemptMatcher.isOverBroad) {
            throw SanitizerError.exemptPatternTooBroad(pattern: broad)
        }
        // Also fail closed if exempt_paths covers one of skillet's own **synthetic artifact labels** (the
        // always-scanned core surfaces) — path-exempting them is a `--no-sanitize` via config (constitution
        // R5). Value-level false positives belong in betterleaks' own allowlist. (Body keys now scan under
        // their REAL path, so "paths" is no longer a label.) Keep in sync with `BundleText.scanInputs`.
        for artifact in ["transcript.md", "diff", "trace.json"]
        where ExemptMatcher.isExempt(artifact, patterns: exemptPaths) {
            throw SanitizerError.exemptCoversSyntheticArtifact(artifact: artifact)
        }
        let findings = try await scanner.scan(artifacts.scanInputs.map { ScanInput(path: $0.path, text: $0.text) })
        // Drop exempt-path findings (a silenced false positive is never added to the redaction set).
        // `exempt_paths` is glob / whole-segment (plan 014 §4), not an exact-string set.
        let kept = findings.filter { !ExemptMatcher.isExempt($0.file, patterns: exemptPaths) }
        // Distinct (value, rule) pairs are the redaction SET; `redactions` in the report SUMS the count of
        // `[REDACTED]` **markers** written across every artifact (maximal merged spans — adjacent repeats
        // collapse into one), so it equals exactly the markers a reader can grep in the bundle. (R4-2 only
        // fixes it as a single Int; distinct-secret detail stays in the in-memory report.)
        let secrets = Array(Set(kept.map { Redactor.Secret(value: $0.secret, rule: $0.ruleID) }))
        var markers = 0
        let redacted = artifacts.redacting {
            let r = Redactor.redact($0, secrets: secrets)
            markers += r.redactions
            return r.text
        }
        return (redacted, SanitizationReport(scanner: "betterleaks", version: version, redactions: markers))
    }
}
