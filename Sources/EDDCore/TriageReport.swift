import Foundation

/// The `skillet.triage/1` machine payload (`skillet triage --json`) — the corpus failure taxonomy
/// (design §6.1, F33). Emitted via ``SkilletJSON`` (snake_case, schema-stamped). **Frozen boundary**
/// format: additive within the major, golden-tested. Mirrors exactly the facts the human table shows —
/// nothing speculative (Specs/016 assumption 1).
public struct TriageReport: SchemaIdentified, Codable, Sendable, Equatable {
    public static let schema = "skillet.triage/1"
    public let skills: [SkillTriage]
    public let dryRun: Bool
    public init(skills: [SkillTriage], dryRun: Bool) {
        self.skills = skills; self.dryRun = dryRun
    }
}

/// One skill's triage: its clusters plus the corpus-health notes (staleness, coverage, disclosures).
public struct SkillTriage: Codable, Sendable, Equatable {
    public let skill: String
    public let clusters: [TriageClusterRow]
    /// Recordings whose cached SARIF was scored by a different (or unknown) skillet version (D1).
    public let staleRecordings: Int
    public let totalRecordings: Int
    /// `SKILL-S000` disclosures — scoring *coverage*, not a failure cluster (Specs/016 A7).
    public let unreadableHits: Int
    /// Inputs triage could not use, each with its reason — the visible dead-letter channel; never a
    /// silent skip (Specs/016 round 2).
    public let disclosures: [TriageDisclosure]
    /// Relative paths of finding files written this run (empty under `--dry-run` or when none were new).
    public let written: [String]
    public init(skill: String, clusters: [TriageClusterRow], staleRecordings: Int, totalRecordings: Int,
                unreadableHits: Int, disclosures: [TriageDisclosure], written: [String]) {
        self.skill = skill; self.clusters = clusters
        self.staleRecordings = staleRecordings; self.totalRecordings = totalRecordings
        self.unreadableHits = unreadableHits; self.disclosures = disclosures; self.written = written
    }
}

/// One failure cluster (= one scorer rule that fired, D2), ranked by frequency. `lever` is the
/// routing **hypothesis, not a verdict**; `worstLevel` stays a raw string (tolerant of future levels).
public struct TriageClusterRow: Codable, Sendable, Equatable {
    public let cluster: String
    public let ruleId: String
    public let hits: Int
    public let recordings: [String]
    public let totalRecordings: Int
    public let worstLevel: String
    public let lever: Lever
    public let confidence: Confidence
    /// The finding-file outcome for this cluster. The engine sets the intent — `new` (would be written;
    /// what `--dry-run` shows), `exists` (a finding is already on file), `closed-still-firing` (a human
    /// closed it; reported, never auto-reopened — Specs/016 D3) — and on a real (non-dry-run) write the
    /// command **finalizes** a would-be-`new` to what actually happened: `written`, `blocked-exists` (a
    /// file already occupied the path), or `write-failed` (the write itself errored). Additive values
    /// (round 15): a consumer reads this field alone to know the outcome, no cross-referencing.
    public let fileStatus: String
    /// The finding's id (`<date>-<slug>`) — the stem of `findings/<id>.md`.
    public let findingId: String
    /// The finding's current lifecycle state when one exists on file.
    public let state: LifecycleState?
    /// Friction-event ids sharing a session with this cluster — the computed join (D6), never stored.
    public let linkedFriction: [String]
    public init(cluster: String, ruleId: String, hits: Int, recordings: [String], totalRecordings: Int,
                worstLevel: String, lever: Lever, confidence: Confidence, fileStatus: String,
                findingId: String, state: LifecycleState?, linkedFriction: [String]) {
        self.cluster = cluster; self.ruleId = ruleId; self.hits = hits; self.recordings = recordings
        self.totalRecordings = totalRecordings; self.worstLevel = worstLevel; self.lever = lever
        self.confidence = confidence; self.fileStatus = fileStatus; self.findingId = findingId
        self.state = state; self.linkedFriction = linkedFriction
    }

    /// A copy with `fileStatus` replaced — how the command finalizes a would-be-`new` row to its real
    /// write outcome (round 15). Every other field is unchanged.
    public func withFileStatus(_ status: String) -> TriageClusterRow {
        TriageClusterRow(cluster: cluster, ruleId: ruleId, hits: hits, recordings: recordings,
                         totalRecordings: totalRecordings, worstLevel: worstLevel, lever: lever,
                         confidence: confidence, fileStatus: status, findingId: findingId,
                         state: state, linkedFriction: linkedFriction)
    }
}

/// An input triage saw but could not use — surfaced, never silently dropped.
public struct TriageDisclosure: Codable, Sendable, Equatable {
    public let subject: String
    public let reason: String
    public init(subject: String, reason: String) { self.subject = subject; self.reason = reason }
}
