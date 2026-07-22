import Testing
import Foundation

/// Drives `skillet triage` through the built binary over a synthetic captured corpus (F33): cached
/// bundle SARIFs in, ranked clusters + written `skillet.finding/1` files out. Free and deterministic —
/// no model, no network, no re-scoring.
@Suite("skillet triage via the binary", .tags(.integration))
struct TriageIntegrationTests {
    /// A discoverable project with one skill and a captured-corpus `sessions/` dir. Each bundle is the
    /// two files triage reads — snake_case meta + camelCase SARIF, the exact shapes capture writes.
    static func makeTriageRepo(
        skill: String = "demo",
        bundles: [(stem: String, toolVersion: String, results: [(rule: String, level: String, message: String)])]
    ) throws -> URL {
        let root = try Fixture.makeTempDirectory()
        try "project:\n  skills_root: skills\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let dir = root.appendingPathComponent("skills/\(skill)", isDirectory: true)
        let sessions = dir.appendingPathComponent("evaluations/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try "---\nname: \(skill)\ndescription: triage integration fixture\n---\nBody.\n"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        for bundle in bundles {
            try #"{"id": "\#(bundle.stem)", "skill": "\#(skill)", "skill_version": "1.0.0", "model": "opus", "harness": "claude-code", "captured_at": "2026-06-01T00:00:00Z", "schema_version": 2}"#
                .write(to: sessions.appendingPathComponent("\(bundle.stem).session-meta.json"),
                       atomically: true, encoding: .utf8)
            let results = bundle.results.map {
                #"{"ruleId": "\#($0.rule)", "level": "\#($0.level)", "message": {"text": "\#($0.message)"}}"#
            }.joined(separator: ",")
            try #"{"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "skillet", "version": "\#(bundle.toolVersion)"}}, "results": [\#(results)]}]}"#
                .write(to: sessions.appendingPathComponent("\(bundle.stem).audit-input.sarif"),
                       atomically: true, encoding: .utf8)
        }
        return root
    }

    /// The running skillet version (for fixtures that must NOT be stale) — asked of the binary itself,
    /// since IntegrationTests deliberately import no kits.
    static func currentVersion() async throws -> String {
        let out = try await SkilletHarness().run(["--version"])
        return out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("End-to-end: clusters, finding file written in the F29 field order, exit 0")
    func endToEnd() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [
            ("2026-06-01-a", version, [("SKILL-S001", "warning", "delve"), ("SKILL-S001", "error", "leverage")]),
            ("2026-06-02-b", version, [("SKILL-S001", "warning", "delve again")]),
        ])
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("triage — demo"))
        #expect(out.stdout.contains("slop-vocabulary"))
        #expect(out.stdout.contains("skill_md (hypothesis)"))
        #expect(!out.stdout.contains("scored by a different skillet version"))   // fresh corpus: no staleness

        let findingURL = root.appendingPathComponent("skills/demo/evaluations/findings")
        let files = try FileManager.default.contentsOfDirectory(atPath: findingURL.path)
        #expect(files.count == 1)
        let name = try #require(files.first)
        #expect(name.hasSuffix("-slop-vocabulary.md"))
        let text = try String(contentsOf: findingURL.appendingPathComponent(name), encoding: .utf8)
        // The F29 emitted field order (Specs/016 A6) — strictly increasing positions.
        let keys = ["schema:", "id:", "skill:", "domain:", "lever:", "state:", "sessions:",
                    "skill_version:", "model:", "source:", "confidence:", "cluster:", "signal:"]
        let positions = keys.compactMap { text.range(of: $0)?.lowerBound }
        #expect(positions.count == keys.count)
        #expect(positions == positions.sorted())
        #expect(text.contains("cluster: slop-vocabulary"))
        #expect(text.contains("state: logged"))
        #expect(text.contains("hits=3 recordings=2/2 worst=error"))
        #expect(text.contains("hypothesis, not a verdict"))
        #expect(text.hasSuffix("\n"))                                            // POSIX-terminated
    }

    @Test("Re-run never touches the existing finding (byte-identical) and reports `exists`")
    func reRunSkips() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S002", "warning", "m")])])
        defer { Fixture.remove(root) }
        _ = try await SkilletHarness().run(["-C", root.path, "triage"])
        let findingsDir = root.appendingPathComponent("skills/demo/evaluations/findings")
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: findingsDir.path).first)
        let url = findingsDir.appendingPathComponent(name)
        let before = try Data(contentsOf: url)

        let second = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(second.exitCode == 0)
        #expect(second.stdout.contains("exists (logged)"))
        #expect(!second.stdout.contains("wrote"))
        #expect(try Data(contentsOf: url) == before)                             // byte-identical (D3)
    }

    @Test("A human-closed cluster still firing is reported, never reopened or duplicated")
    func closedStillFiring() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }
        let findingsDir = root.appendingPathComponent("skills/demo/evaluations/findings")
        try FileManager.default.createDirectory(at: findingsDir, withIntermediateDirectories: true)
        let closed = """
        ---
        schema: skillet.finding/1
        id: 2026-07-01-slop-vocabulary
        skill: demo
        domain: demo
        lever: skill_md
        state: closed
        state_reason: fixed in SKILL.md v2
        sessions: [2026-05-01-old]
        source: scorer
        confidence: high
        cluster: slop-vocabulary
        ---
        closed by hand
        """
        try closed.write(to: findingsDir.appendingPathComponent("2026-07-01-slop-vocabulary.md"),
                         atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("still firing"))
        let files = try FileManager.default.contentsOfDirectory(atPath: findingsDir.path)
        #expect(files == ["2026-07-01-slop-vocabulary.md"])                      // no duplicate written
    }

    @Test("--dry-run previews without writing; --json emits skillet.triage/1")
    func dryRunAndJSON() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S004", "error", "m")])])
        defer { Fixture.remove(root) }
        let dry = try await SkilletHarness().run(["-C", root.path, "triage", "--dry-run"])
        #expect(dry.exitCode == 0)
        #expect(dry.stdout.contains("(dry-run: no files written)"))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("skills/demo/evaluations/findings").path))

        let json = try await SkilletHarness().run(["-C", root.path, "triage", "--dry-run", "--json"])
        #expect(json.stdout.contains(#""schema":"skillet.triage/1""#))
        #expect(json.stdout.contains(#""cluster":"rule-of-three""#))
        #expect(json.stdout.contains(#""dry_run":true"#))
    }

    @Test("Footer guard: the unshipped `next` appears only in once-it-lands prose, never as the actionable suggestion")
    func footerGuard() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.stdout.contains("`skillet next` picks them up once it lands"))   // prose fallback
        #expect(!out.stdout.contains("→ next: skillet next"))                        // no actionable unregistered suggestion
    }

    @Test("Friction sharing a session is joined and printed; staleness notes an old-version bundle")
    func frictionJoinAndStaleness() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [
            ("2026-06-01-a", version, [("SKILL-S001", "warning", "m")]),
            ("2026-06-02-b", "0.0.1", []),                                       // stale vintage
        ])
        defer { Fixture.remove(root) }
        let frictionDir = root.appendingPathComponent("skills/demo/evaluations/friction")
        try FileManager.default.createDirectory(at: frictionDir, withIntermediateDirectories: true)
        try """
        ---
        schema: skillet.friction/1
        id: 2026-06-07-hand-fixed-vocab
        skill: demo
        domain: demo
        lever: skill_md
        state: logged
        sessions: [2026-06-01-a]
        ---
        had to strip the slop by hand
        """.write(to: frictionDir.appendingPathComponent("2026-06-07-hand-fixed-vocab.md"),
                  atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.stdout.contains("shares session(s) with friction: 2026-06-07-hand-fixed-vocab"))
        #expect(out.stdout.contains("1 of 2 recording(s) scored by a different skillet version"))
    }

    @Test("--since that excludes everything names the filter, never claims an empty corpus (round 12)")
    func sinceExcludingAllNamesTheFilter() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "triage", "--since", "2099-01-01"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("predate --since 2099-01-01"))
        #expect(out.stdout.contains("not empty, only filtered"))
        #expect(!out.stdout.contains("no recordings yet"))   // the misleading claim round 12 removes
        // Round 16: the closing hint names the filter, not "record a session".
        #expect(out.stdout.contains("no recordings on or after 2099-01-01 — widen --since"))
        #expect(!out.stdout.contains("record a session — skillet capture"))
    }

    @Test("A symlinked evidence file is surfaced (not silently skipped), naming the consequence (round 16)")
    func symlinkedEvidenceIsSurfaced() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }
        let findingsDir = root.appendingPathComponent("skills/demo/evaluations/findings")
        try FileManager.default.createDirectory(at: findingsDir, withIntermediateDirectories: true)
        // A symlinked `.md` where an evidence file belongs → surfaced, never followed.
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: outside) }
        try "external".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: findingsDir.appendingPathComponent("2026-05-01-x.md"), withDestinationURL: outside)

        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("findings/2026-05-01-x.md"))                   // named
        #expect(out.stdout.contains("is a symbolic link — not followed"))          // surfaced (not silent)
        #expect(out.stdout.contains("records were not counted"))                   // consequence spelled out
    }

    @Test("Multi-skill footer targets the skill that produced results, not whichever sorted first (round 12)")
    func multiSkillFooterTargetsTheProductiveSkill() async throws {
        let version = try await Self.currentVersion()
        // "demo" has the corpus + clusters; "alpha" (sorts FIRST) is an empty shell.
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }
        let alpha = root.appendingPathComponent("skills/alpha", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try "---\nname: alpha\ndescription: empty shell\n---\nB.\n"
            .write(to: alpha.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("evaluations/demo/findings"))    // the skill with results
        #expect(!out.stdout.contains("evaluations/alpha/findings"))  // not the alphabetical accident
    }

    @Test("Empty corpus exits 0 and points at capture; bad --since and unknown skill are usage errors")
    func edgesAndUsage() async throws {
        let root = try Self.makeTriageRepo(bundles: [])
        defer { Fixture.remove(root) }
        let empty = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(empty.exitCode == 0)
        #expect(empty.stdout.contains("no recordings yet"))
        #expect(empty.stdout.contains("skillet capture --skill demo"))

        let badSince = try await SkilletHarness().run(["-C", root.path, "triage", "--since", "junk"])
        #expect(badSince.exitCode == 2)
        // Round 2: semantic validation — shape-valid but impossible dates are usage errors, not
        // silent empty-match filters.
        let badMonth = try await SkilletHarness().run(["-C", root.path, "triage", "--since", "2026-13-01"])
        #expect(badMonth.exitCode == 2)
        let unknown = try await SkilletHarness().run(["-C", root.path, "triage", "ghost"])
        #expect(unknown.exitCode == 2)                                           // shared selection helper
    }

    @Test("An empty skills tree gives real guidance, never literal <skill>/<slug> placeholders (round 5)")
    func noSkillsNoPlaceholders() async throws {
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }
        try "project:\n  skills_root: skills\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("skills"), withIntermediateDirectories: true)   // empty tree
        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("no skills found"))
        #expect(out.stdout.contains("add a skill"))
        #expect(!out.stdout.contains("<skill>"))    // the round-5 leak
        #expect(!out.stdout.contains("<slug>"))
    }

    @Test("An all-corrupt corpus surfaces disclosures, not a silent 'no recordings' (round 5)")
    func allCorruptSurfaced() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }
        // Corrupt the only bundle's SARIF → 0 usable bundles, 1 disclosure — must still be visible.
        try "not json{".write(
            to: root.appendingPathComponent("skills/demo/evaluations/sessions/2026-06-01-a.audit-input.sarif"),
            atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)                                  // reporter: disclosed, not fatal
        #expect(out.stdout.contains("no usable recordings"))
        #expect(out.stdout.contains("2026-06-01-a"))                // the disclosed stem
        #expect(out.stdout.contains("not valid JSON"))
        #expect(!out.stdout.contains("no recordings yet"))          // never the misleading line
    }

    @Test("Evidence scan guards findings/ + friction/: non-regular entries disclosed (never read), hidden silently skipped (round 7)")
    func evidenceScanGuardsNonRegularAndHidden() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }
        let findingsDir = root.appendingPathComponent("skills/demo/evaluations/findings")
        try FileManager.default.createDirectory(at: findingsDir, withIntermediateDirectories: true)
        // A DIRECTORY named like an evidence file → must be disclosed, never `String(contentsOf:)`-read
        // (a FIFO here would hang forever; a directory exercises the identical `isRegularFile` guard).
        try FileManager.default.createDirectory(
            at: findingsDir.appendingPathComponent("2026-01-01-x.md"), withIntermediateDirectories: true)
        // A HIDDEN `.md` (e.g. an editor lock) → silently skipped, like every directory probe.
        try "not evidence".write(to: findingsDir.appendingPathComponent(".#lock.md"),
                                 atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)                                              // no hang, no crash
        #expect(out.stdout.contains("findings/2026-01-01-x.md: not a plain regular file"))   // round 8 unified the message
        #expect(!out.stdout.contains(".#lock.md"))                             // hidden → never mentioned
        #expect(out.stdout.contains("slop-vocabulary"))                        // the real bundle still triaged
    }

    @Test("A hard-linked evidence file is refused, never read (findings/ scan; round 8)")
    func hardLinkedEvidenceRefused() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }
        let findingsDir = root.appendingPathComponent("skills/demo/evaluations/findings")
        try FileManager.default.createDirectory(at: findingsDir, withIntermediateDirectories: true)
        // A valid finding OUTSIDE the project, hard-linked into findings/ → linkCount 2 → must be refused.
        let external = root.deletingLastPathComponent().appendingPathComponent("external-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: external) }
        try """
        ---
        schema: skillet.finding/1
        id: 2026-05-01-external
        skill: demo
        domain: demo
        lever: skill_md
        state: closed
        state_reason: injected via hard link
        sessions: [2026-06-01-a]
        source: scorer
        confidence: high
        cluster: slop-vocabulary
        ---
        external content
        """.write(to: external, atomically: true, encoding: .utf8)
        try FileManager.default.linkItem(at: external, to: findingsDir.appendingPathComponent("2026-05-01-external.md"))

        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("findings/2026-05-01-external.md: not a plain regular file"))
        // The hard-linked "closed" finding was NOT read, so slop-vocabulary is written fresh, not
        // closed-still-firing — proof the external content never influenced triage.
        #expect(out.stdout.contains("written: findings/"))
        #expect(!out.stdout.contains("still firing"))
    }

    @Test("A file where a folder belongs is flagged specifically, never 'no recordings' (round 15, finding 2)")
    func fileWhereADirectoryBelongsIsFlagged() async throws {
        // A regular file occupying evaluations/sessions must NOT read as an empty corpus — it's a
        // certain misconfiguration, surfaced with what/where/how; the reporter continues at exit 0.
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }
        try "project:\n  skills_root: skills\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let evalDir = root.appendingPathComponent("skills/demo/evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: x\n---\nB.\n"
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        // A FILE named `sessions` where the recordings folder should be.
        try "not a folder".write(to: evalDir.appendingPathComponent("sessions"), atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)                                                   // reporter: notes, continues
        #expect(out.stdout.contains("demo/evaluations/sessions"))                    // where
        #expect(out.stdout.contains("is a file, not a directory"))                   // what
        #expect(out.stdout.contains("remove or rename it"))                          // how
        #expect(!out.stdout.contains("no recordings yet"))                           // never the red herring
    }

    @Test("A filename collision is disclosed with a clean cluster name and never overwritten")
    func collisionDisclosedCleanly() async throws {
        let version = try await Self.currentVersion()
        let root = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(root) }
        // Pre-plant an UNDECODABLE file at exactly the id triage would synthesize today: it yields no
        // cluster ref (disclosed as undecodable), so the engine synthesizes `slop-vocabulary` fresh —
        // and the write path must hit the collision, disclose it cleanly (round 3: this line rendered
        // `Optional("slop-vocabulary")`), and leave the planted file untouched.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let findingsDir = root.appendingPathComponent("skills/demo/evaluations/findings")
        try FileManager.default.createDirectory(at: findingsDir, withIntermediateDirectories: true)
        let planted = findingsDir.appendingPathComponent("\(today)-slop-vocabulary.md")
        try "not a finding at all".write(to: planted, atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 0)                                               // disclosed, not fatal
        #expect(out.stdout.contains("'slop-vocabulary' finding was not written"))
        #expect(!out.stdout.contains("Optional("))                               // the round-3 regression
        // Round 10/15: the table agrees with the disclosure — blocked-exists, never "new"/"written".
        #expect(out.stdout.contains("blocked — findings/\(today)-slop-vocabulary.md already exists"))
        #expect(!out.stdout.contains("new: findings/"))
        #expect(try String(contentsOf: planted, encoding: .utf8) == "not a finding at all")
    }

    @Test("A symlinked skill directory is unreachable: invisible to discovery, unknown by name, nothing written through it")
    func symlinkedSkillUnreachable() async throws {
        let version = try await Self.currentVersion()
        // A real skill corpus OUTSIDE the project, reachable only through a symlinked skills/<skill>.
        // Empirically (round 2), discovery does NOT follow directory symlinks (`isDirectoryKey` reports
        // the link itself), so the symlinked skill never enumerates — and requesting it by name is an
        // unknown-skill usage error. Either way, triage neither reads nor writes through the link.
        let outside = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(outside) }
        let root = try Fixture.makeTempDirectory()
        defer { Fixture.remove(root) }
        try "project:\n  skills_root: skills\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let skills = root.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: skills.appendingPathComponent("evil"),
            withDestinationURL: outside.appendingPathComponent("skills/demo"))

        let bare = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(bare.exitCode == 0)                                              // nothing discovered → no-op
        #expect(!bare.stdout.contains("slop-vocabulary"))                        // outside corpus never read
        let byName = try await SkilletHarness().run(["-C", root.path, "triage", "evil"])
        #expect(byName.exitCode == 2)                                            // unknown skill (not discovered)
        // Nothing was written through the link into the outside corpus.
        #expect(!FileManager.default.fileExists(
            atPath: outside.appendingPathComponent("skills/demo/evaluations/findings").path))
    }

    @Test("A symlinked evaluations/sessions component is refused (no reads through it)")
    func symlinkedSessionsRefused() async throws {
        let version = try await Self.currentVersion()
        let outside = try Self.makeTriageRepo(bundles: [("2026-06-01-a", version, [("SKILL-S001", "warning", "m")])])
        defer { Fixture.remove(outside) }
        let root = try Self.makeTriageRepo(bundles: [])                          // a legit skill, empty corpus
        defer { Fixture.remove(root) }
        let sessions = root.appendingPathComponent("skills/demo/evaluations/sessions")
        try FileManager.default.removeItem(at: sessions)
        try FileManager.default.createSymbolicLink(
            at: sessions,
            withDestinationURL: outside.appendingPathComponent("skills/demo/evaluations/sessions"))

        let out = try await SkilletHarness().run(["-C", root.path, "triage"])
        #expect(out.exitCode == 4)
        #expect(out.stderr.contains("symlink"))
        #expect(!out.stdout.contains("slop-vocabulary"))                         // the outside corpus was never read
    }
}
