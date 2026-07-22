import Foundation
import EDDCore

/// One scorer rule's triage identity: its stable cluster slug, its cheapest-lever routing hypothesis,
/// and its per-rule detector confidence (Specs/016 D2/D4/D5).
public struct TriageRule: Sendable, Equatable {
    public let ruleId: String
    /// The cluster name — the re-run-stable grouping key downstream recurrence-counting relies on.
    public let slug: String
    /// Where the fix most cheaply belongs — printed with the standing "hypothesis, not a verdict"
    /// caveat; the human re-routes by editing the finding file's `lever`.
    public let lever: Lever
    /// Per-rule detector trust (the CodeQL `@precision` / Semgrep `metadata.confidence` model) —
    /// orthogonal to severity, never derived from recurrence.
    public let confidence: Confidence
}

/// The fixed, code-backed routing + confidence catalog (D4/D5 — the project's settled "fixed catalog"
/// stance; no config surface). One row per scorer rule; the taxonomy grows only by **adding scorer
/// rules**, never by changing existing keys (D2). `SKILL-S000` is deliberately absent: an unreadable
/// file is scoring *coverage*, not a skill-failure cluster (A7).
public enum TriageTable {
    /// The coverage-disclosure rule, reported as a note rather than clustered.
    public static let coverageRuleId = "SKILL-S000"

    public static let rules: [TriageRule] = [
        // Prose-style rules: a standing SKILL.md instruction is the cheapest durable fix.
        TriageRule(ruleId: "SKILL-S001", slug: "slop-vocabulary", lever: .skillMd, confidence: .high),
        TriageRule(ruleId: "SKILL-S002", slug: "puffery", lever: .skillMd, confidence: .high),
        TriageRule(ruleId: "SKILL-S003", slug: "em-dash", lever: .skillMd, confidence: .high),
        TriageRule(ruleId: "SKILL-S004", slug: "rule-of-three", lever: .skillMd, confidence: .high),
        TriageRule(ruleId: "SKILL-S005", slug: "knowledge-cutoff", lever: .skillMd, confidence: .high),
        // Experimental + default-off pattern heuristic → medium detector confidence (D5).
        TriageRule(ruleId: "SKILL-S006", slug: "not-x-but-y", lever: .skillMd, confidence: .medium),
        // Structural output validity → a validity eval is the strong lever.
        TriageRule(ruleId: "SKILL-S007", slug: "sarif-validity", lever: .eval, confidence: .high),
    ]

    public static func rule(for ruleId: String) -> TriageRule? {
        rules.first { $0.ruleId == ruleId }
    }
}
