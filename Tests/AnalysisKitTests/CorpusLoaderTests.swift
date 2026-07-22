import Testing
import Foundation
import EDDCore
@testable import AnalysisKit

@Suite("CorpusLoader — union-stem enumeration + tolerant decode (F33 shell)")
struct CorpusLoaderTests {
    /// A fresh temp sessions dir per test.
    func makeDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skillet-loader-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    func write(_ text: String, _ name: String, in dir: URL) throws {
        try Data(text.utf8).write(to: dir.appendingPathComponent(name))
    }
    /// The shape capture writes (camelCase SARIF; snake_case meta) — Specs/016 assumption 6.
    func meta(_ stem: String, skillVersion: String = "1.0.0") -> String {
        """
        {"id": "\(stem)", "skill": "s", "skill_version": "\(skillVersion)", "model": "opus",
         "harness": "claude-code", "captured_at": "2026-06-01T00:00:00Z", "schema_version": 2}
        """
    }
    func sarif(version: String = "0.4.0", results: String = "") -> String {
        """
        {"version": "2.1.0", "runs": [{
          "tool": {"driver": {"name": "skillet", "version": "\(version)"}},
          "results": [\(results)]}]}
        """
    }

    @Test func loadsACompleteBundle() throws {
        let dir = try makeDir()
        try write(meta("2026-06-01-a"), "2026-06-01-a.session-meta.json", in: dir)
        try write(sarif(results: #"{"ruleId": "SKILL-S001", "level": "warning", "message": {"text": "m"}}"#),
                  "2026-06-01-a.audit-input.sarif", in: dir)
        let (bundles, disclosures) = CorpusLoader().load(sessionsDir: dir)
        #expect(disclosures.isEmpty)
        let b = try #require(bundles.first)
        #expect(b.stem == "2026-06-01-a")
        #expect(b.skillVersion == "1.0.0")
        #expect(b.model == "opus")
        #expect(b.toolVersion == "0.4.0")
        #expect(b.results == [SarifResultSlice(ruleId: "SKILL-S001", level: "warning", message: "m")])
    }

    @Test func unionStemsDiscloseHalfBundlesNeverSilentlySkip() throws {
        // Round 2: a SARIF-only stem and a meta-only stem must BOTH surface as disclosures.
        // Round 4: hidden entries never enumerate (the project-wide directory-probe convention).
        let dir = try makeDir()
        try write(sarif(), "2026-06-01-sarif-only.audit-input.sarif", in: dir)
        try write(meta("2026-06-02-meta-only"), "2026-06-02-meta-only.session-meta.json", in: dir)
        try write("junk", ".DS_Store", in: dir)
        try write(meta(".sneaky"), ".sneaky.session-meta.json", in: dir)
        let (bundles, disclosures) = CorpusLoader().load(sessionsDir: dir)
        #expect(bundles.isEmpty)
        #expect(disclosures.count == 2)
        #expect(!disclosures.contains { $0.subject.contains("sneaky") || $0.subject.contains("DS_Store") })
        #expect(disclosures.contains { $0.subject == "2026-06-01-sarif-only" && $0.reason.contains("missing session-meta.json") })
        #expect(disclosures.contains { $0.subject == "2026-06-02-meta-only" && $0.reason.contains("missing audit-input.sarif") })
    }

    @Test func sinceExcludingEverythingDisclosesTheFilterNotEmptiness() throws {
        // Round 12: a date filter that excluded every recording must NOT read as an empty corpus —
        // the zero-results-from-filter rule (name the constraint, not "no data").
        let dir = try makeDir()
        for stem in ["2026-06-01-a", "2026-06-02-b"] {
            try write(meta(stem), "\(stem).session-meta.json", in: dir)
            try write(sarif(), "\(stem).audit-input.sarif", in: dir)
        }
        let (bundles, disclosures) = CorpusLoader().load(sessionsDir: dir, since: "2027-01-01")
        #expect(bundles.isEmpty)
        #expect(disclosures.count == 1)
        #expect(disclosures[0].reason.contains("2 recording(s) predate --since 2027-01-01"))
        #expect(disclosures[0].reason.contains("not empty, only filtered"))
        // A PARTIAL match stays quiet — no confusion exists when something got through.
        let (partial, partialDisclosures) = CorpusLoader().load(sessionsDir: dir, since: "2026-06-02")
        #expect(partial.map(\.stem) == ["2026-06-02-b"])
        #expect(partialDisclosures.isEmpty)
    }

    @Test func sinceFiltersByStemDatePrefixInclusive() throws {
        let dir = try makeDir()
        for stem in ["2026-06-01-old", "2026-06-05-mid", "2026-06-09-new"] {
            try write(meta(stem), "\(stem).session-meta.json", in: dir)
            try write(sarif(), "\(stem).audit-input.sarif", in: dir)
        }
        let (bundles, _) = CorpusLoader().load(sessionsDir: dir, since: "2026-06-05")
        #expect(bundles.map(\.stem) == ["2026-06-05-mid", "2026-06-09-new"])
    }

    @Test func symlinkedEntriesAreSkippedNeverFollowed() throws {
        let dir = try makeDir()
        // A real bundle, plus a symlink pretending to be another bundle's meta (points at the real one).
        try write(meta("2026-06-01-a"), "2026-06-01-a.session-meta.json", in: dir)
        try write(sarif(), "2026-06-01-a.audit-input.sarif", in: dir)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("2026-06-02-fake.session-meta.json"),
            withDestinationURL: dir.appendingPathComponent("2026-06-01-a.session-meta.json"))
        let (bundles, disclosures) = CorpusLoader().load(sessionsDir: dir)
        #expect(bundles.map(\.stem) == ["2026-06-01-a"])          // the symlink stem never enumerates
        #expect(!disclosures.contains { $0.subject.contains("fake") })
    }

    @Test func corruptJSONIsDisclosedNotFatal() throws {
        let dir = try makeDir()
        try write("not json{", "2026-06-01-a.session-meta.json", in: dir)
        try write(sarif(), "2026-06-01-a.audit-input.sarif", in: dir)
        try write(meta("2026-06-02-b"), "2026-06-02-b.session-meta.json", in: dir)
        try write("also not json", "2026-06-02-b.audit-input.sarif", in: dir)
        let (bundles, disclosures) = CorpusLoader().load(sessionsDir: dir)
        #expect(bundles.isEmpty)
        #expect(disclosures.contains { $0.subject == "2026-06-01-a" && $0.reason.contains("session-meta.json is not valid JSON") })
        #expect(disclosures.contains { $0.subject == "2026-06-02-b" && $0.reason.contains("audit-input.sarif is not valid JSON") })
    }

    @Test func nonRegularBundleFilesAreGuardedNeverRead() throws {
        // Round 6: a dir/FIFO/socket/device named like a bundle file must never reach `boundedRead`
        // (a FIFO would hang the FileHandle open forever). A DIRECTORY exercises the same
        // `isRegularFile` guard safely — dir and FIFO are both non-regular, both refused before any read.
        let dir = try makeDir()
        // A regular meta seeds the stem; its sarif sibling is a DIRECTORY → the read site must refuse it
        // (the mixed case the enumeration guard alone would miss).
        try write(meta("2026-06-01-a"), "2026-06-01-a.session-meta.json", in: dir)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("2026-06-01-a.audit-input.sarif"), withIntermediateDirectories: true)
        // A LONE directory masquerading as a bundle file → skipped during the walk, never a stem.
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("2026-06-02-b.session-meta.json"), withIntermediateDirectories: true)
        let (bundles, disclosures) = CorpusLoader().load(sessionsDir: dir)
        #expect(bundles.isEmpty)
        #expect(disclosures.contains { $0.subject == "2026-06-01-a" && $0.reason.contains("not a regular file") })
        #expect(!disclosures.contains { $0.subject == "2026-06-02-b" })   // lone non-regular → walk-skipped, not a candidate
    }

    @Test func hiddenSiblingIsNeverReferencedBecauseStemsShareHiddenness() throws {
        // Round-10 refutation: a planted HIDDEN sarif beside a visible meta is claimed readable — it
        // isn't, structurally: both of a stem's filenames share the stem prefix, so they're either both
        // hidden or both visible. The loader constructs the VISIBLE sibling name (which doesn't exist)
        // and discloses "missing"; the hidden plant has a different filename and is never referenced.
        let dir = try makeDir()
        try write(meta("2026-06-01-a"), "2026-06-01-a.session-meta.json", in: dir)
        try write(sarif(results: #"{"ruleId": "SKILL-S001", "level": "warning", "message": {"text": "planted"}}"#),
                  ".2026-06-01-a.audit-input.sarif", in: dir)   // the hidden plant
        let (bundles, disclosures) = CorpusLoader().load(sessionsDir: dir)
        #expect(bundles.isEmpty)                                 // the plant never becomes the sibling
        #expect(disclosures.count == 1)
        #expect(disclosures.contains { $0.subject == "2026-06-01-a" && $0.reason.contains("missing audit-input.sarif") })
    }

    @Test func hardLinkedBundleFilesAreRefusedNeverRead() throws {
        // Round 8: a hard link (linkCount > 1) points at another inode — possibly a file outside the
        // project the symlink guard can't catch (CWE-59/CWE-62). Refuse + disclose, like the rest of
        // the codebase (BodyExtractor / ClaudeCodeAdapter / WorkspaceManager).
        let dir = try makeDir()
        try write(meta("2026-06-01-a"), "2026-06-01-a.session-meta.json", in: dir)
        // A valid SARIF OUTSIDE sessions/, hard-linked in → the in-corpus entry has linkCount 2.
        try write(sarif(results: #"{"ruleId": "SKILL-S001", "level": "warning", "message": {"text": "m"}}"#),
                  "external.sarif", in: dir.deletingLastPathComponent())
        try FileManager.default.linkItem(
            at: dir.deletingLastPathComponent().appendingPathComponent("external.sarif"),
            to: dir.appendingPathComponent("2026-06-01-a.audit-input.sarif"))
        let (bundles, disclosures) = CorpusLoader().load(sessionsDir: dir)
        #expect(bundles.isEmpty)   // the linked SARIF is refused → bundle incomplete, never decoded
        #expect(disclosures.contains { $0.subject == "2026-06-01-a" && $0.reason.contains("hard link") })
    }

    @Test func missingDirectoryYieldsEmptyNotError() {
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skillet-loader-ghost-\(UUID().uuidString)/sessions")
        let (bundles, disclosures) = CorpusLoader().load(sessionsDir: ghost)
        #expect(bundles.isEmpty && disclosures.isEmpty)   // no corpus yet — not an error
    }
}
