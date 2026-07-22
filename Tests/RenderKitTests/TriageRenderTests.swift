import Testing
import EDDCore
@testable import RenderKit

@Suite("renderTriage — human table + skillet.triage/1 (F33)")
struct TriageRenderTests {
    let renderer = Renderer(mode: .human, color: ColorPolicy.resolve(choice: .never, noColorEnv: false, isTTY: false))

    func report(dryRun: Bool = false) -> TriageReport {
        TriageReport(
            skills: [SkillTriage(
                skill: "docc-articles",
                clusters: [TriageClusterRow(
                    cluster: "slop-vocabulary", ruleId: "SKILL-S001", hits: 12,
                    recordings: ["2026-06-01-a"], totalRecordings: 2, worstLevel: "error",
                    lever: .skillMd, confidence: .high, fileStatus: "written",
                    findingId: "2026-07-19-slop-vocabulary", state: nil,
                    linkedFriction: ["2026-06-07-f1"])],
                staleRecordings: 1, totalRecordings: 2, unreadableHits: 1,
                disclosures: [TriageDisclosure(subject: "2026-06-09-c", reason: "missing session-meta.json")],
                written: ["findings/2026-07-19-slop-vocabulary.md"])],
            dryRun: dryRun)
    }

    @Test func humanTableCarriesNotesClustersJoinsAndCaveat() throws {
        let out = try renderer.renderTriage(report(), nextSteps: ["review findings"]).stdout
        #expect(out.contains("triage — docc-articles"))
        #expect(out.contains("1 of 2 recording(s) scored by a different skillet version"))   // staleness first
        #expect(out.contains("unreadable-file disclosure"))                                  // coverage note
        #expect(out.contains("slop-vocabulary"))
        #expect(out.contains("skill_md (hypothesis)"))
        #expect(out.contains("written: findings/2026-07-19-slop-vocabulary.md"))
        #expect(out.contains("shares session(s) with friction: 2026-06-07-f1"))              // computed join
        #expect(out.contains("hypothesis, not a verdict"))                                   // standing caveat
        #expect(out.contains("2026-06-09-c: missing session-meta.json"))                     // disclosure
        #expect(out.contains("wrote 1 finding file(s)"))
        #expect(out.contains("→ next: review findings"))
    }

    @Test func dryRunSaysSoAndEmptyCorpusPointsAtCapture() throws {
        let dry = try renderer.renderTriage(report(dryRun: true)).stdout
        #expect(dry.contains("(dry-run: no files written)"))
        #expect(!dry.contains("wrote 1"))
        // Round 4: the footer is run-level — exactly ONE occurrence even across multiple skills.
        let two = TriageReport(skills: report().skills + report().skills, dryRun: true)
        let out = try renderer.renderTriage(two).stdout
        #expect(out.components(separatedBy: "(dry-run: no files written)").count == 2)   // one marker
        let empty = TriageReport(
            skills: [SkillTriage(skill: "s", clusters: [], staleRecordings: 0, totalRecordings: 0,
                                 unreadableHits: 0, disclosures: [], written: [])], dryRun: false)
        #expect(try renderer.renderTriage(empty).stdout.contains("no recordings yet"))
    }

    @Test func writeOutcomesRenderDistinctLabelsNeverMislabeled() throws {
        // Round 15 (Unknown 1=B): the FILE column reads the finalized `fileStatus` directly, so a write
        // ERROR is never mislabeled "a file exists", and each outcome has its own word.
        func row(_ status: String, _ id: String) -> TriageClusterRow {
            TriageClusterRow(cluster: "slop-vocabulary", ruleId: "SKILL-S001", hits: 1,
                             recordings: ["2026-06-01-a"], totalRecordings: 1, worstLevel: "warning",
                             lever: .skillMd, confidence: .high, fileStatus: status,
                             findingId: id, state: nil, linkedFriction: [])
        }
        let report = TriageReport(
            skills: [SkillTriage(skill: "demo",
                clusters: [row("written", "w"), row("blocked-exists", "b"), row("write-failed", "f")],
                staleRecordings: 0, totalRecordings: 1, unreadableHits: 0, disclosures: [], written: ["findings/w.md"])],
            dryRun: false)
        let out = try renderer.renderTriage(report).stdout
        #expect(out.contains("written: findings/w.md"))
        #expect(out.contains("blocked — findings/b.md already exists (see note)"))
        #expect(out.contains("write failed — findings/f.md (see note)"))   // NOT "already exists"
        #expect(!out.contains("write failed — findings/f.md already exists"))
    }

    @Test func emptyCorpusWithDisclosuresSurfacesThemNeverSilent() throws {
        // Round 5: totalRecordings == 0 must not swallow loader disclosures (unreadable dir / all-corrupt
        // bundles). The dead-letter channel is never silent.
        let report = TriageReport(
            skills: [SkillTriage(skill: "demo", clusters: [], staleRecordings: 0, totalRecordings: 0,
                                 unreadableHits: 0,
                                 disclosures: [TriageDisclosure(subject: "sessions", reason: "sessions directory unreadable")],
                                 written: [])],
            dryRun: false)
        let out = try renderer.renderTriage(report).stdout
        #expect(out.contains("no usable recordings"))
        #expect(out.contains("sessions: sessions directory unreadable"))
        #expect(!out.contains("no recordings yet"))   // the misleading "just capture one" hint is suppressed
    }

    @Test func noSkillsPrintsAClearBodyLine() throws {
        let empty = TriageReport(skills: [], dryRun: false)
        #expect(try renderer.renderTriage(empty).stdout.contains("no skills found — nothing to triage"))
    }

    @Test func jsonModeEmitsTheSchemaStampedPayload() throws {
        let json = Renderer(mode: .json, color: renderer.color)
        let out = try json.renderTriage(report()).stdout
        #expect(out.contains(#""schema":"skillet.triage/1""#))
        #expect(out.hasSuffix("\n"))
    }
}
