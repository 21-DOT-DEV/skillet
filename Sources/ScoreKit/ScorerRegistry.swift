import Foundation
import EDDCore

/// The scorer set and the static SARIF rule catalog.
public enum ScorerRegistry {
    /// All density scorers, in stable rule-id order.
    static let all: [any Scorer] = [
        SlopVocabularyScorer(), PufferyScorer(), EmDashScorer(),
        RuleOfThreeScorer(), KnowledgeCutoffScorer(), NotXButYScorer(),
    ]

    /// Experimental, default-off checks (§4.7) — run only when opted in via `scorers.enable`.
    static let defaultOff: Set<String> = ["SKILL-S006"]

    /// The scorers active for this run: `disable` turns a default-on check off (and **wins** over
    /// `enable`); a default-off check runs only if listed in `enable`.
    static func active(_ config: SkilletConfig.Scorers) -> [any Scorer] {
        let disable = Set(config.disable), enable = Set(config.enable)
        return all.filter { s in
            if disable.contains(s.ruleId) { return false }
            if defaultOff.contains(s.ruleId) { return enable.contains(s.ruleId) }
            return true
        }
    }

    /// The full static rule catalog (S000–S007) for `tool.driver.rules` — advertised whether or not each
    /// rule fires this run (the SARIF-idiomatic "advertise your catalog" model).
    public static let catalog: [SarifRule] = [
        SarifRule(id: "SKILL-S000", name: "file-unreadable", shortDescription: "File not scored"),
        SarifRule(id: "SKILL-S001", name: "slop-vocabulary", shortDescription: "Over-used AI vocabulary"),
        SarifRule(id: "SKILL-S002", name: "puffery", shortDescription: "Marketing-puffery language"),
        SarifRule(id: "SKILL-S003", name: "em-dash", shortDescription: "Em-dash over-use"),
        SarifRule(id: "SKILL-S004", name: "rule-of-three", shortDescription: "Rule-of-three over-use"),
        SarifRule(id: "SKILL-S005", name: "knowledge-cutoff", shortDescription: "Knowledge-cutoff mention"),
        SarifRule(id: "SKILL-S006", name: "not-x-but-y", shortDescription: "Negative-parallelism over-use",
                  properties: ["skillet.enabledByDefault": .bool(false)]),
        SarifRule(id: "SKILL-S007", name: "sarif-validity", shortDescription: "Emitted findings-file validity"),
    ]
}
