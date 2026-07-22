import Foundation
import EDDCore

// MARK: - Engine inputs (already-decoded, in-memory — the functional core takes no filesystem)

/// One usable bundle: its stem (= the session id evidence links on) plus the decoded fields triage
/// consumes. Built by `CorpusLoader` (the shell); the engine never sees a URL.
public struct BundleInput: Sendable, Equatable {
    public let stem: String
    public let skillVersion: String?
    public let model: String?
    /// The scorer version recorded in the bundle's cached SARIF (`nil` = unrecorded → counted stale).
    public let toolVersion: String?
    public let results: [SarifResultSlice]
    public init(stem: String, skillVersion: String?, model: String?, toolVersion: String?,
                results: [SarifResultSlice]) {
        self.stem = stem; self.skillVersion = skillVersion; self.model = model
        self.toolVersion = toolVersion; self.results = results
    }
}

/// An input the loader (or engine) saw but could not use — the visible dead-letter channel.
public struct DisclosedInput: Sendable, Equatable {
    public let subject: String
    public let reason: String
    public init(subject: String, reason: String) { self.subject = subject; self.reason = reason }
}

/// An already-on-file finding, reduced to what re-run matching needs (D3: match by the `cluster`
/// field *inside* the file, never by filename).
public struct ExistingFindingRef: Sendable, Equatable {
    public let id: String
    public let cluster: String?
    public let state: LifecycleState
    public init(id: String, cluster: String?, state: LifecycleState) {
        self.id = id; self.cluster = cluster; self.state = state
    }
}

/// A friction event reduced to the join key (D6: shared session ids, computed live).
public struct FrictionRef: Sendable, Equatable {
    public let id: String
    public let sessions: [String]
    public init(id: String, sessions: [String]) { self.id = id; self.sessions = sessions }
}

// MARK: - Engine outputs

/// A finding the shell should write (`findings/<id>.md`) — the typed record plus its prose body.
public struct NewFinding: Sendable, Equatable {
    public let finding: Finding
    public let body: String
    public init(finding: Finding, body: String) { self.finding = finding; self.body = body }
}

/// One skill's pure triage result; the shell adds write outcomes and renders.
public struct SkillTriageResult: Sendable, Equatable {
    public let clusters: [TriageClusterRow]
    public let newFindings: [NewFinding]
    public let staleRecordings: Int
    public let totalRecordings: Int
    public let unreadableHits: Int
    public let disclosures: [DisclosedInput]

    // Public like every sibling input/output type (round 11 — the missing memberwise init made this
    // the one engine type other modules could consume but never construct, e.g. in tests).
    public init(clusters: [TriageClusterRow], newFindings: [NewFinding], staleRecordings: Int,
                totalRecordings: Int, unreadableHits: Int, disclosures: [DisclosedInput]) {
        self.clusters = clusters; self.newFindings = newFindings
        self.staleRecordings = staleRecordings; self.totalRecordings = totalRecordings
        self.unreadableHits = unreadableHits; self.disclosures = disclosures
    }
}

// MARK: - The engine (pure)

/// The Track-A triage core (F33): cluster cached scorer hits by rule (D2), route + stamp confidence
/// from the fixed table (D4/D5), synthesize finding records for clusters not yet on file (D3), and
/// join to friction via shared sessions (D6). Pure functions over in-memory inputs — deterministic,
/// unit-tested with zero filesystem (P8; functional core).
public enum TriageEngine {
    /// Severity rank for "worst level" — unknown strings rank lowest but still display verbatim.
    private static let levelRank: [String: Int] = ["error": 3, "warning": 2, "note": 1, "none": 0]

    public static func triage(
        skill: String,
        runDate: String,
        runningVersion: String,
        bundles: [BundleInput],
        disclosures loaderDisclosures: [DisclosedInput],
        existingFindings: [ExistingFindingRef],
        friction: [FrictionRef]
    ) -> SkillTriageResult {
        var disclosures = loaderDisclosures
        let sorted = bundles.sorted { $0.stem < $1.stem }   // deterministic aggregation order

        // Staleness (D1): a bundle scored by a different — or unrecorded — skillet version.
        let stale = sorted.filter { $0.toolVersion != runningVersion }.count

        // Aggregate hits per rule; S000 → coverage; unknown rule ids → disclosed, never clustered
        // (the fixed table IS the taxonomy — an unknown id means a newer/foreign scorer).
        struct Accumulator { var hits = 0; var stems: [String] = []; var worst: String?; var worstRank = -1; var example: String? }
        var perRule: [String: Accumulator] = [:]
        var unknownRules: [String: Int] = [:]
        var unreadableHits = 0
        var malformed: [String: Int] = [:]   // stem → results missing a ruleId

        for bundle in sorted {
            for slice in bundle.results {
                guard let ruleId = slice.ruleId else {
                    malformed[bundle.stem, default: 0] += 1
                    continue
                }
                if ruleId == TriageTable.coverageRuleId { unreadableHits += 1; continue }
                guard TriageTable.rule(for: ruleId) != nil else {
                    unknownRules[ruleId, default: 0] += 1
                    continue
                }
                var acc = perRule[ruleId] ?? Accumulator()
                acc.hits += 1
                if acc.stems.last != bundle.stem { acc.stems.append(bundle.stem) }
                // SARIF §3.27.10: an **absent** level defaults to "warning" (the slices carry no
                // per-rule defaultLevel, so the spec's terminal default applies); an **unrecognized**
                // level survives verbatim (tolerant reader), ranked lowest. The first hit always sets
                // `worst` (round 1: `-1 > -1` left an all-unknown cluster's worst level empty).
                let effective = slice.level ?? "warning"
                let rank = levelRank[effective] ?? -1
                if acc.worst == nil || rank > acc.worstRank { acc.worstRank = rank; acc.worst = effective }
                if acc.example == nil, let message = slice.message, !message.isEmpty { acc.example = message }
                perRule[ruleId] = acc
            }
        }
        for (stem, count) in malformed.sorted(by: { $0.key < $1.key }) {
            disclosures.append(DisclosedInput(
                subject: stem, reason: "\(count) SARIF result(s) without a ruleId — not clustered"))
        }
        for (ruleId, count) in unknownRules.sorted(by: { $0.key < $1.key }) {
            disclosures.append(DisclosedInput(
                subject: ruleId,
                reason: "unknown rule id (\(count) hit(s)) — not clustered; upgrade skillet or add the rule to the triage table"))
        }

        // Rank the taxonomy: hits desc, then slug asc (stable across re-runs).
        let ranked = perRule.compactMap { ruleId, acc -> (TriageRule, Accumulator)? in
            TriageTable.rule(for: ruleId).map { ($0, acc) }
        }.sorted { left, right in
            left.1.hits != right.1.hits ? left.1.hits > right.1.hits : left.0.slug < right.0.slug
        }

        var rows: [TriageClusterRow] = []
        var newFindings: [NewFinding] = []
        for (rule, acc) in ranked {
            let recordings = acc.stems.sorted()
            // The computed join (D6): friction events sharing any session with this cluster.
            let linked = friction
                .filter { !Set($0.sessions).isDisjoint(with: recordings) }
                .map(\.id).sorted()
            let existing = existingFindings.first { $0.cluster == rule.slug }
            let status: String
            let findingId: String
            if let existing {
                status = existing.state == .closed ? "closed-still-firing" : "exists"
                findingId = existing.id
            } else {
                status = "new"
                findingId = "\(runDate)-\(rule.slug)"
                let synthesized = synthesize(
                    rule: rule, id: findingId, skill: skill, hits: acc.hits, recordings: recordings,
                    totalRecordings: sorted.count, worstLevel: acc.worst ?? "unknown", example: acc.example,
                    bundles: sorted)
                newFindings.append(synthesized)
            }
            rows.append(TriageClusterRow(
                cluster: rule.slug, ruleId: rule.ruleId, hits: acc.hits, recordings: recordings,
                totalRecordings: sorted.count, worstLevel: acc.worst ?? "unknown", lever: rule.lever,
                confidence: rule.confidence, fileStatus: status, findingId: findingId,
                state: existing?.state, linkedFriction: linked))
        }

        return SkillTriageResult(
            clusters: rows, newFindings: newFindings, staleRecordings: stale,
            totalRecordings: sorted.count, unreadableHits: unreadableHits, disclosures: disclosures)
    }

    // MARK: - Finding synthesis (A6)

    private static func synthesize(
        rule: TriageRule, id: String, skill: String, hits: Int, recordings: [String],
        totalRecordings: Int, worstLevel: String, example: String?, bundles: [BundleInput]
    ) -> NewFinding {
        let contributing = bundles.filter { recordings.contains($0.stem) }
        let header = EvidenceHeader(
            id: id, skill: skill,
            domain: skill,                                   // sentinel (A6/H): can only undercount corroboration
            lever: rule.lever, state: .logged,
            sessions: recordings,
            skillVersion: unanimous(contributing.map(\.skillVersion)),
            model: unanimous(contributing.map(\.model)))
        let signal = "hits=\(hits) recordings=\(recordings.count)/\(totalRecordings) worst=\(worstLevel)"
        let finding = Finding(header: header, source: .scorer, confidence: rule.confidence,
                              cluster: rule.slug, signal: signal)

        var body = "Corpus triage (Track A): \(hits) hit(s) of \(rule.ruleId) across "
        body += "\(recordings.count) of \(totalRecordings) recording(s); worst level: \(worstLevel).\n"
        if let example {
            body += "\nExample: \(example)\n"
        }
        body += "\nRecordings:\n"
        for bundle in contributing {
            let count = bundle.results.filter { $0.ruleId == rule.ruleId }.count
            body += "- \(bundle.stem): \(count) hit(s)\n"
        }
        body += "\nRouting: lever=\(rule.lever.rawValue) — a hypothesis, not a verdict "
        body += "(edit this file's `lever` to re-route).\n"
        return NewFinding(finding: finding, body: body)
    }

    /// All contributing bundles agree on a non-nil value → that value; anything else → the `"unknown"`
    /// sentinel (A6 — the F29 header allows it; diversity readings count it separately).
    private static func unanimous(_ values: [String?]) -> String {
        let present = Set(values.compactMap { $0 })
        // `present.first` is non-nil under the `count == 1` guard; `?? "unknown"` drops the force-unwrap
        // (repo no-`!` convention) without changing behavior (round 16).
        return (present.count == 1 && !values.contains(nil)) ? (present.first ?? "unknown") : "unknown"
    }
}
