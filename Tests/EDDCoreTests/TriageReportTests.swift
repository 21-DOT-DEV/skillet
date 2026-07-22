import Testing
import Foundation
@testable import EDDCore

@Suite("TriageReport — the frozen skillet.triage/1 boundary format (F33)")
struct TriageReportTests {
    func sample() -> TriageReport {
        TriageReport(
            skills: [SkillTriage(
                skill: "docc-articles",
                clusters: [TriageClusterRow(
                    cluster: "slop-vocabulary", ruleId: "SKILL-S001", hits: 12,
                    recordings: ["2026-06-01-a", "2026-06-04-b"], totalRecordings: 3,
                    worstLevel: "error", lever: .skillMd, confidence: .high,
                    fileStatus: "new", findingId: "2026-07-19-slop-vocabulary",
                    state: nil, linkedFriction: ["2026-06-07-snippets-dont-compile"])],
                staleRecordings: 1, totalRecordings: 3, unreadableHits: 2,
                disclosures: [TriageDisclosure(subject: "2026-06-09-c",
                                               reason: "missing session-meta.json")],
                written: ["findings/2026-07-19-slop-vocabulary.md"])],
            dryRun: false)
    }

    /// Golden: enumerate ALL fields (F8 policy — an omitted field is an unenforced freeze). Semantic
    /// JSON comparison, since byte-stable sortedKeys isn't guaranteed cross-platform.
    @Test func encodesTheGoldenShape() throws {
        let golden = """
        {"schema": "skillet.triage/1", "dry_run": false, "skills": [{
          "skill": "docc-articles",
          "clusters": [{
            "cluster": "slop-vocabulary", "rule_id": "SKILL-S001", "hits": 12,
            "recordings": ["2026-06-01-a", "2026-06-04-b"], "total_recordings": 3,
            "worst_level": "error", "lever": "skill_md", "confidence": "high",
            "file_status": "new", "finding_id": "2026-07-19-slop-vocabulary",
            "linked_friction": ["2026-06-07-snippets-dont-compile"]
          }],
          "stale_recordings": 1, "total_recordings": 3, "unreadable_hits": 2,
          "disclosures": [{"subject": "2026-06-09-c", "reason": "missing session-meta.json"}],
          "written": ["findings/2026-07-19-slop-vocabulary.md"]
        }]}
        """
        #expect(try jsonSemanticEqual(try SkilletJSON.encode(sample()), golden))
    }

    @Test func roundTripsThroughTheSharedDecoder() throws {
        let encoded = try SkilletJSON.encode(sample())
        let back = try SkilletJSON.decoder().decode(TriageReport.self, from: Data(encoded.utf8))
        #expect(back == sample())
    }

    @Test func distinctWriteOutcomesRoundTripInTheMachineFormat() throws {
        // Round 15 (Unknown 1=B): a consumer reads `file_status` alone to know the outcome.
        for status in ["written", "blocked-exists", "write-failed", "new"] {
            let row = TriageClusterRow(
                cluster: "c", ruleId: "SKILL-S001", hits: 1, recordings: ["a"], totalRecordings: 1,
                worstLevel: "warning", lever: .skillMd, confidence: .high, fileStatus: status,
                findingId: "2026-07-21-c", state: nil, linkedFriction: [])
            #expect(row.withFileStatus("write-failed").fileStatus == "write-failed")   // finalizer helper
            let json = try SkilletJSON.encode(TriageReport(
                skills: [SkillTriage(skill: "s", clusters: [row], staleRecordings: 0, totalRecordings: 1,
                                     unreadableHits: 0, disclosures: [], written: [])], dryRun: false))
            #expect(json.contains(#""file_status":"\#(status)""#))
        }
    }

    @Test func existingStateEncodesWhenPresent() throws {
        let row = TriageClusterRow(
            cluster: "puffery", ruleId: "SKILL-S002", hits: 1, recordings: ["2026-06-01-a"],
            totalRecordings: 1, worstLevel: "warning", lever: .skillMd, confidence: .high,
            fileStatus: "closed-still-firing", findingId: "2026-07-01-puffery",
            state: .closed, linkedFriction: [])
        let json = try SkilletJSON.encode(TriageReport(
            skills: [SkillTriage(skill: "s", clusters: [row], staleRecordings: 0, totalRecordings: 1,
                                 unreadableHits: 0, disclosures: [], written: [])],
            dryRun: true))
        #expect(json.contains(#""state":"closed""#))
        #expect(json.contains(#""file_status":"closed-still-firing""#))
        #expect(json.contains(#""dry_run":true"#))
    }
}
