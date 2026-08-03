import Testing
import Foundation

/// `skillet suggest` through the built binary. Every case is $0: the model call is replaced by a canned
/// reply via the private `--reply-file` seam, and the paths that must *refuse before spending* are
/// asserted with **no** reply file present, so a regression that spends would fail to resolve a model
/// program rather than silently pass.
@Suite("skillet suggest via the binary", .tags(.integration))
struct SuggestIntegrationTests {
    static let goodReply = #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"Use the rule of three when density guidance calls for it.","rationale":"Absolute phrasing drove over-application.","addresses":["2026-06-09-slop"]}]}"#

    /// A project with one skill, one machine-mined finding, and (optionally) a human note.
    static func makeRepo(judgeModel: String? = "claude-sonnet-4-6", judgeProvider: String = "claude-code",
                         suggestModel: String? = nil, friction: Bool = false,
                         findingEval: String? = nil) throws -> URL {
        let root = try Fixture.makeTempDirectory()
        var yaml = "project:\n  skills_root: skills\njudge:\n  provider: \(judgeProvider)\n"
        if let judgeModel { yaml += "  model: \(judgeModel)\n" }
        if let suggestModel { yaml += "suggest:\n  model: \(suggestModel)\n" }
        try yaml.write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)

        let skill = root.appendingPathComponent("skills/demo", isDirectory: true)
        let findings = skill.appendingPathComponent("evaluations/findings", isDirectory: true)
        let frictionDir = skill.appendingPathComponent("evaluations/friction", isDirectory: true)
        try FileManager.default.createDirectory(at: findings, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: frictionDir, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: A demo skill for drafting, long enough to satisfy the lint rules.\n---\n# Guide\n\nAlways use the rule of three.\n"
            .write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        var head = "---\nschema: skillet.finding/1\nid: 2026-06-09-slop\nskill: demo\ndomain: demo\nlever: skill_md\nstate: logged\nsessions: [s1]\nskill_version: \"1.0\"\nmodel: opus\n"
        if let findingEval { head += "eval: \(findingEval)\n" }
        head += "source: scorer\nconfidence: high\ncluster: slop-vocabulary\n---\nhits=12 recordings=3/5 worst=error\n"
        try head.write(to: findings.appendingPathComponent("2026-06-09-slop.md"), atomically: true, encoding: .utf8)

        if friction {
            try "---\nschema: skillet.friction/1\nid: 2026-06-10-handfix\nskill: demo\ndomain: demo\nlever: skill_md\nstate: logged\nsessions: [s1]\nskill_version: \"1.0\"\nmodel: opus\n---\nI had to rewrite the intro by hand.\n"
                .write(to: frictionDir.appendingPathComponent("2026-06-10-handfix.md"), atomically: true, encoding: .utf8)
        }
        return root
    }

    static func writeReply(_ body: String, in root: URL, named: String = "reply.json") throws -> String {
        let url = root.appendingPathComponent(named)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: - the happy path

    @Test("Drafts from a finding: writes one proposal file, exits 0, and the JSON summary names it")
    func draftsAndWrites() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply, "--json"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("\"schema\":\"skillet.suggest/1\""))
        #expect(out.stdout.contains("\"edits\":1"))
        #expect(out.stdout.contains(".skillet/proposals/"))
        // Report-and-point: the summary must NOT carry the edit text.
        #expect(!out.stdout.contains("current_excerpt"))

        // The drafted file landed, and the cache is self-ignoring even though `init` never ran here.
        let proposals = root.appendingPathComponent(".skillet/proposals")
        let files = try FileManager.default.contentsOfDirectory(atPath: proposals.path)
        #expect(files.count == 1 && files[0].hasSuffix(".json"))
        let written = try String(contentsOf: proposals.appendingPathComponent(files[0]), encoding: .utf8)
        #expect(written.contains("\"schema\":\"skillet.proposal/1\""))
        #expect(written.contains("\"skill_md_lines\":\"7\""))          // derived from the verified match
        // Self-ignoring on purpose (the convention auto-generated cache folders use), and
        // self-documenting so nobody "fixes" it later.
        let ignore = try String(contentsOf: root.appendingPathComponent(".skillet/.gitignore"), encoding: .utf8)
        #expect(ignore.contains("*"))
        #expect(ignore.contains("Created by skillet automatically"))
        #expect(!ignore.contains("!.gitignore"))
    }

    @Test("A hand-written note is a valid source, exactly like a machine-mined finding")
    func draftsFromFriction() async throws {
        let root = try Self.makeRepo(friction: true); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(
            #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"x","rationale":"r","addresses":["2026-06-10-handfix"]}]}"#,
            in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-10-handfix", "--reply-file", reply, "--json"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("2026-06-10-handfix"))
        #expect(out.stdout.contains("\"edits\":1"))
    }

    @Test("A dry run spends nothing and writes nothing, but reports the estimate")
    func dryRunWritesNothing() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // No --reply-file: if the command tried to call a model it would fail resolving one.
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "-n"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("prompt size"))
        #expect(out.stdout.contains("nothing sent, nothing written"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".skillet/proposals").path))
    }

    // MARK: - refusals that must happen BEFORE spending

    @Test("Naming no evidence, an unknown id, or an unknown skill is misuse — and never reaches a model")
    func misuseRefusals() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let noEvidence = try await SkilletHarness().run(["-C", root.path, "suggest", "demo"])
        #expect(noEvidence.exitCode == 2)
        #expect(noEvidence.stderr.contains("--from"))

        let unknownId = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "not-a-real-id"])
        #expect(unknownId.exitCode == 2)
        #expect(unknownId.stderr.contains("not-a-real-id"))

        let unknownSkill = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "ghost", "--from", "2026-06-09-slop"])
        #expect(unknownSkill.exitCode == 2)
    }

    @Test("An id present in BOTH evidence folders is refused as ambiguous, naming the collision")
    func ambiguousEvidenceId() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // Same id in friction/ as in findings/.
        try "---\nschema: skillet.friction/1\nid: 2026-06-09-slop\nskill: demo\ndomain: demo\nlever: skill_md\nstate: logged\nsessions: [s1]\nskill_version: \"1.0\"\nmodel: opus\n---\nnote\n"
            .write(to: root.appendingPathComponent("skills/demo/evaluations/friction/2026-06-09-slop.md"),
                   atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("ambiguous"))
    }

    @Test("No drafting model anywhere is misuse; a foreign grading service blocks only the borrowed model")
    func modelResolution() async throws {
        let none = try Self.makeRepo(judgeModel: nil); defer { Fixture.remove(none) }
        let noModel = try await SkilletHarness().run(
            ["-C", none.path, "suggest", "demo", "--from", "2026-06-09-slop"])
        #expect(noModel.exitCode == 2)
        #expect(noModel.stderr.contains("model"))

        // A different grading service must not have its model handed to the claude program…
        let foreign = try Self.makeRepo(judgeProvider: "opencode"); defer { Fixture.remove(foreign) }
        let borrowedBlocked = try await SkilletHarness().run(
            ["-C", foreign.path, "suggest", "demo", "--from", "2026-06-09-slop"])
        #expect(borrowedBlocked.exitCode == 2)
        #expect(borrowedBlocked.stderr.contains("opencode"))

        // …but an explicitly-set drafting model has no service setting to contradict, so it proceeds.
        let explicit = try Self.makeRepo(judgeProvider: "opencode", suggestModel: "claude-opus-5")
        defer { Fixture.remove(explicit) }
        let reply = try Self.writeReply(Self.goodReply, in: explicit)
        let ok = try await SkilletHarness().run(
            ["-C", explicit.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply, "--json"])
        #expect(ok.exitCode == 0)
        #expect(ok.stdout.contains("claude-opus-5"))
    }

    @Test("`--out` must be a bare .json filename")
    func outNameShape() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        for bad in ["notes", "../escape.json", "sub/dir.json"] {
            let out = try await SkilletHarness().run(
                ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--out", bad, "--reply-file", reply])
            #expect(out.exitCode == 2, "\(bad) should be refused")
        }
        let good = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--out", "fix.json", "--reply-file", reply])
        #expect(good.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".skillet/proposals/fix.json").path))
    }

    @Test("A second draft with the same name is a disclosed refusal, never a clobber")
    func collisionIsDisclosed() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let args = ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--out", "fix.json", "--reply-file", reply]
        #expect(try await SkilletHarness().run(args).exitCode == 0)
        let again = try await SkilletHarness().run(args)
        #expect(again.exitCode == 0)                              // reporter, not a gate
        #expect(again.stdout.contains("already exists"))
    }

    @Test("A reply that isn't a draft fails as a bad artifact, showing what came back")
    func unparseableReply() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply("Here's the JSON: {\"edits\":[]}", in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply])
        #expect(out.exitCode == 4)
        #expect(out.stderr.contains("Here's the JSON"))           // the excerpt, so it's diagnosable
    }

    @Test("An unreadable named record is fatal, not skipped — a draft never proceeds on partial evidence")
    func namedEvidenceFailureIsFatal() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let findings = root.appendingPathComponent("skills/demo/evaluations/findings")
        let outside = root.deletingLastPathComponent().appendingPathComponent("out-\(UUID().uuidString).md")
        try "external".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        // The id must be well-formed, or it is refused for its *shape* before any read and this test
        // would stop exercising the read-refusal path it exists to guard.
        try FileManager.default.createSymbolicLink(
            at: findings.appendingPathComponent("2026-06-11-linked.md"), withDestinationURL: outside)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-11-linked"])
        #expect(out.exitCode == 4)
        #expect(out.stderr.contains("symlink"))
    }

    @Test("An empty proof list is stated plainly, with what to do about it")
    func emptyProofListIsExplained() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply])
        #expect(out.stdout.contains("no eval is linked to this evidence yet"))

        // With a linked eval, it is reported instead — copied from the record, never invented.
        let linked = try Self.makeRepo(findingEval: "rule-of-three-density"); defer { Fixture.remove(linked) }
        let reply2 = try Self.writeReply(Self.goodReply, in: linked)
        let withEval = try await SkilletHarness().run(
            ["-C", linked.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply2, "--json"])
        #expect(withEval.stdout.contains("\"expected\":[\"rule-of-three-density\"]"))
    }

    // MARK: - the three contract fixes (verified end-to-end; each would otherwise revert unnoticed)

    /// Writes a skill file of roughly `bytes`, in few enough lines to stay clear of the body-length
    /// lint rule (which runs *before* this check and would otherwise mask it).
    static func inflateSkillFile(_ root: URL, bytes: Int) throws {
        let head = "---\nname: demo\ndescription: A demo skill for drafting, long enough to satisfy the lint rules.\n---\n"
        let line = String(repeating: "x", count: 2000) + "\n"
        var body = ""
        while head.utf8.count + body.utf8.count < bytes { body += line }
        try (head + body).write(to: root.appendingPathComponent("skills/demo/SKILL.md"),
                                atomically: true, encoding: .utf8)
    }

    /// Boundary test, **both sides** of the real shipped limit — a one-sided test would still pass with
    /// the comparison inverted or the constant wrong in the permissive direction.
    ///
    /// Limitation, stated rather than implied: driving this through the binary means the request is the
    /// skill file *plus* instructions and evidence, so these straddle the limit by a margin rather than
    /// landing on the exact byte. That catches a wrong constant or a flipped comparison; it would not
    /// catch a literal one-byte off-by-one.
    @Test("The prompt-size limit refuses with the gate status; under it, and with --yes, drafting proceeds")
    func promptCeilingBothSides() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }

        // Over the limit, no override ⇒ refused at the gate status, and no model program is contacted
        // (there is no --reply-file here, so reaching the call would surface as a *different* failure).
        try Self.inflateSkillFile(root, bytes: 400_000)
        let over = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"])
        #expect(over.exitCode == 5, "over the limit must be the gate status, not misuse")
        #expect(over.stderr.contains("ceiling"))

        // Same input with the override ⇒ the check is released, so it gets far enough to fail resolving
        // a model program (exit 3). Proves --yes passes the gate rather than skipping the work.
        let overridden = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--yes"])
        #expect(overridden.exitCode == 3, "--yes must release the gate, not bypass the command")

        // Comfortably under the limit ⇒ never gated; again reaches model resolution instead.
        try Self.inflateSkillFile(root, bytes: 20_000)
        let under = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"])
        #expect(under.exitCode == 3, "under the limit must not be gated")
        #expect(!under.stderr.contains("ceiling"))
    }

    @Test("A malformed `suggest:` settings block fails loudly instead of quietly using the grading model")
    func malformedSuggestSectionIsFatal() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // `model` must be a string; a list is malformed. This once fell through to the grading model in
        // silence, because the section was read by a separate decoder that swallowed the failure.
        try "project:\n  skills_root: skills\njudge:\n  provider: claude-code\n  model: claude-sonnet-4-6\nsuggest:\n  model: [not, a, string]\n"
            .write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "-n"])
        #expect(out.exitCode == 4)
        // Names the offending key, not merely the file — the settings decoder's own detail is now
        // carried through, so this is more specific than the message it replaced.
        #expect(out.stderr.contains("suggest.model"))
    }

    @Test("An unreadable human note is reported, not silently dropped from the join")
    func unreadableFrictionIsDisclosed() async throws {
        let root = try Self.makeRepo(friction: true); defer { Fixture.remove(root) }
        let frictionDir = root.appendingPathComponent("skills/demo/evaluations/friction")
        try FileManager.default.createSymbolicLink(
            at: frictionDir.appendingPathComponent("broken.md"),
            withDestinationURL: URL(fileURLWithPath: "/nonexistent-target"))
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply])
        #expect(out.exitCode == 0)                                   // best-effort context, still reported
        #expect(out.stdout.contains("friction/broken.md"))
        #expect(out.stdout.contains("symlink"))
        // A legitimately absent folder must stay silent — only a wrong-type or unreadable one is surfaced.
        let quiet = try Self.makeRepo(); defer { Fixture.remove(quiet) }
        try FileManager.default.removeItem(at: quiet.appendingPathComponent("skills/demo/evaluations/friction"))
        let reply2 = try Self.writeReply(Self.goodReply, in: quiet)
        let out2 = try await SkilletHarness().run(
            ["-C", quiet.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply2])
        #expect(!out2.stdout.contains("friction"))
    }

    @Test("An evidence id cannot escape the skill folder — traversal is refused before any file is opened")
    func evidenceIdCannotTraverse() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // A real, readable markdown file OUTSIDE the project, of exactly the shape the reader would accept.
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).md")
        try "---\nschema: skillet.finding/1\nid: 2026-01-01-outside\n---\nsecret\n"
            .write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let escaped = "../../../../" + outside.deletingPathExtension().lastPathComponent
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", escaped])
        #expect(out.exitCode == 2, "a traversing id is refused as misuse")
        #expect(out.stderr.contains("not a valid evidence id"))
        // Echoing back the id the user typed is fine and helpful. What must NOT happen is confirming
        // whether anything is really there, or emitting a byte of it — that is what would turn a bad id
        // into a way to probe the filesystem.
        #expect(!out.stdout.contains("secret") && !out.stderr.contains("secret"))
        #expect(!out.stderr.lowercased().contains("exists"))
        #expect(!out.stderr.contains("no evidence named"))   // the message used when a path IS checked

        // Plain separators and dot segments are refused too, not just the long climb.
        for bad in ["findings/x", "..", "./2026-06-09-slop"] {
            let r = try await SkilletHarness().run(["-C", root.path, "suggest", "demo", "--from", bad])
            #expect(r.exitCode == 2, "\(bad) should be refused")
        }
    }

    @Test("Naming the same evidence twice is the same draft — not a doubled request or a different filename")
    func repeatedEvidenceIdIsDeduplicated() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let once = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply, "-n", "--json"])
        let twice = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--from", "2026-06-09-slop",
             "--reply-file", reply, "-n", "--json"])
        #expect(once.exitCode == 0 && twice.exitCode == 0)
        // Same evidence ⇒ same request size (it isn't sent twice) and the same recorded evidence list.
        #expect(once.stdout == twice.stdout)
    }

    @Test("A named record behind a broken link is refused as unreadable, not reported as missing")
    func danglingLinkIsRefusedNotMissing() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // The target never existed: a presence check that follows links would call this "absent".
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("skills/demo/evaluations/findings/2026-06-12-dangling.md"),
            withDestinationURL: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).md"))
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-12-dangling"])
        #expect(out.exitCode == 4, "a named-but-unreadable record is a bad artifact, not misuse")
        #expect(!out.stderr.contains("no evidence named"))
        // And the error names the REAL folder (plural), not the singular record kind.
        #expect(out.stderr.contains("findings/2026-06-12-dangling.md"))
    }

    @Test("A model program that cannot run is an environment problem — never blamed on the drafts folder")
    func modelLaunchFailureIsEnvironment() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // Point the resolver at a path that is not an executable: the launch fails before any output
        // exists, which is the case a non-zero-exit check alone would miss.
        let notAProgram = root.appendingPathComponent("not-a-program")
        try "#!/bin/sh\nexit 0\n".write(to: notAProgram, atomically: true, encoding: .utf8)
        // deliberately NOT chmod +x — launching it fails
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"],
            environment: ["SKILLET_CLAUDE_CODE_BIN": notAProgram.path])
        #expect(out.exitCode == 3, "an unrunnable model program is an environment failure")
        // The old catch-all reported this as a bad artifact pointing at the drafts folder.
        #expect(!out.stderr.contains(".skillet/proposals"))
        #expect(out.stderr.contains("claude-code"))
    }

    @Test("A plain file where the scratch folder belongs is the project's problem, not reported as our bug")
    func fileBlockingCacheFolderIsAnArtifactError() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // A regular file named like the scratch folder: the symlink guard does not cover this, and the
        // folder-creation call would otherwise throw a raw error that the last-resort handler reports as
        // "a defect in skillet" — blaming ourselves for a malformed repo.
        try "not a directory".write(to: root.appendingPathComponent(".skillet"),
                                    atomically: true, encoding: .utf8)
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply])
        #expect(out.exitCode == 4, "a file blocking the folder is a malformed project, not an internal defect")
        #expect(out.stderr.contains("a directory is expected"))
        #expect(!out.stderr.contains("defect in skillet"))
    }

    @Test("`--out` matches the documented rule exactly — a leading dot is allowed, separators are not")
    func outNameMatchesDocumentedRule() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        // Allowed: a hidden name is harmless in a scratch folder and the contract never forbade it.
        let hidden = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--out", ".draft.json", "--reply-file", reply])
        #expect(hidden.exitCode == 0)
        // Still refused: separators, the parent form, and anything not ending in .json.
        for bad in ["sub/dir.json", "..", "notes"] {
            let r = try await SkilletHarness().run(
                ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--out", bad, "--reply-file", reply])
            #expect(r.exitCode == 2, "\(bad) should be refused")
        }
    }

    @Test("A record filed under one skill but declaring another is refused as misfiled")
    func wrongSkillRecordIsRefused() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // Same folder, but the record says it belongs to a different skill. Drafting from it would
        // ground an edit to `demo` in evidence about something else.
        try "---\nschema: skillet.finding/1\nid: 2026-06-13-elsewhere\nskill: other-skill\ndomain: other-skill\nlever: skill_md\nstate: logged\nsessions: [s1]\nskill_version: \"1.0\"\nmodel: opus\nsource: scorer\nconfidence: high\ncluster: c\n---\nbody\n"
            .write(to: root.appendingPathComponent("skills/demo/evaluations/findings/2026-06-13-elsewhere.md"),
                   atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-13-elsewhere"])
        #expect(out.exitCode == 4)
        #expect(out.stderr.contains("other-skill") && out.stderr.contains("demo"))
    }

    @Test("A file where the evidence folder belongs is diagnosed, not reported as 'no such evidence'")
    func fileWhereEvidenceFolderBelongs() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let findings = root.appendingPathComponent("skills/demo/evaluations/findings")
        try FileManager.default.removeItem(at: findings)
        try "not a directory".write(to: findings, atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"])
        #expect(out.exitCode == 4)
        #expect(out.stderr.contains("a directory is expected"))
        #expect(!out.stderr.contains("no evidence named"))
    }

    @Test("A file where the PARENT evidence folder belongs is diagnosed — not reported as 'no such evidence'")
    func fileWhereParentEvidenceFolderBelongs() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // The parent, not one of its children: paths *inside* it then don't exist, so a check that only
        // inspects the children finds nothing wrong and the lookup quietly returns nothing.
        let evaluations = root.appendingPathComponent("skills/demo/evaluations")
        try FileManager.default.removeItem(at: evaluations)
        try "not a directory".write(to: evaluations, atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"])
        #expect(out.exitCode == 4)
        #expect(out.stderr.contains("evaluations"))
        #expect(out.stderr.contains("a directory is expected"))
        #expect(!out.stderr.contains("no evidence named"))
    }

    @Test("An unknown evidence id names what IS available, or says nothing is recorded yet")
    func unknownEvidenceIdListsAvailable() async throws {
        let root = try Self.makeRepo(friction: true); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-01-01-typo"])
        #expect(out.exitCode == 2)
        // Both folders contribute, sorted — you can paste one straight back.
        #expect(out.stderr.contains("2026-06-09-slop"))
        #expect(out.stderr.contains("2026-06-10-handfix"))

        // With nothing recorded, saying "choose one of: " would be worse than useless.
        let bare = try Self.makeRepo(); defer { Fixture.remove(bare) }
        try FileManager.default.removeItem(
            at: bare.appendingPathComponent("skills/demo/evaluations/findings/2026-06-09-slop.md"))
        let empty = try await SkilletHarness().run(
            ["-C", bare.path, "suggest", "demo", "--from", "2026-01-01-typo"])
        #expect(empty.exitCode == 2)
        #expect(empty.stderr.contains("nothing recorded yet") || empty.stderr.contains("run `skillet triage"))
    }

    @Test("Previewing an oversized request previews it — the size limit guards spending, not looking")
    func previewIsNotBlockedByTheSizeLimit() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        try Self.inflateSkillFile(root, bytes: 400_000)
        // No canned reply: if this reached a model call it would fail resolving one, so exit 0 also
        // proves nothing was contacted.
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "-n"])
        #expect(out.exitCode == 0, "a preview spends nothing, so the spend limit must not refuse it")
        #expect(out.stdout.contains("prompt size"))
        #expect(out.stdout.contains("over the"), "the preview must warn that a real run would be refused")
        #expect(out.stdout.contains("nothing sent, nothing written"))

        // Without preview the limit still bites — the guard moved, it did not disappear.
        let real = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"])
        #expect(real.exitCode == 5)
    }

    @Test("A name already taken by a DIFFERENT draft says so, instead of claiming you already drafted it")
    func nameTakenByDifferentDraftIsNotCalledADuplicate() async throws {
        let root = try Self.makeRepo(friction: true); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let args = ["-C", root.path, "suggest", "demo", "--out", "fix.json", "--reply-file", reply]

        // Same evidence twice ⇒ genuinely a repeat.
        #expect(try await SkilletHarness().run(args + ["--from", "2026-06-09-slop"]).exitCode == 0)
        let repeated = try await SkilletHarness().run(args + ["--from", "2026-06-09-slop"])
        #expect(repeated.stdout.contains("this exact draft already exists"))

        // Different evidence, same requested name ⇒ a different draft, and it must be described as one.
        let reply2 = try Self.writeReply(
            #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"x","rationale":"r","addresses":["2026-06-10-handfix"]}]}"#,
            in: root, named: "reply2.json")
        let different = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-10-handfix", "--out", "fix.json", "--reply-file", reply2])
        // You asked for a draft and got none: reporting success would let a script carry on as though
        // one existed. (A matching draft already being there is different — that IS the state you wanted.)
        #expect(different.exitCode == 2)
        #expect(different.stdout.contains("a different draft already occupies that name"))
        #expect(!different.stdout.contains("this exact draft already exists"))
    }

    @Test("Drafting refuses a blocked model program before spending — the same gate the measured run uses")
    func spendGateBlocksBannedHarness() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // A stand-in program that reports a version the tool refuses to use. No canned reply here, so
        // reaching the model call at all would be a spend.
        let shim = root.appendingPathComponent("claude-shim")
        try "#!/bin/sh\necho '1.0.60 (Claude Code)'\n".write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim.path])
        // Whatever the exact refusal, it must be an environment-class refusal and must not have drafted.
        #expect(out.exitCode == 3, "a blocked or unusable model program must be refused before spending")
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".skillet/proposals").path))
    }

    @Test("Occupied-name reporting tells the three cases apart, including an unreadable file")
    func occupiedNameDistinguishesThreeCases() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)

        // (a) A file that is not a readable draft must NOT be called "a different draft".
        let proposals = root.appendingPathComponent(".skillet/proposals", isDirectory: true)
        try FileManager.default.createDirectory(at: proposals, withIntermediateDirectories: true)
        try "this is not json".write(to: proposals.appendingPathComponent("fix.json"),
                                     atomically: true, encoding: .utf8)
        let unreadable = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--out", "fix.json", "--reply-file", reply])
        #expect(unreadable.exitCode == 2)                                   // nothing of ours was saved
        #expect(unreadable.stdout.contains("could not be read"))
        #expect(!unreadable.stdout.contains("a different draft already occupies"))
        #expect(!unreadable.stdout.contains("this exact draft already exists"))

        // (b) The same draft twice is genuinely a repeat.
        try FileManager.default.removeItem(at: proposals.appendingPathComponent("fix.json"))
        let args = ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--out", "fix.json", "--reply-file", reply]
        #expect(try await SkilletHarness().run(args).exitCode == 0)
        #expect(try await SkilletHarness().run(args).stdout.contains("this exact draft already exists"))
    }

    @Test("Listing the same evidence in a different order is the same draft, not a different one")
    func evidenceOrderDoesNotChangeIdentity() async throws {
        let root = try Self.makeRepo(friction: true); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let a = ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--from", "2026-06-10-handfix",
                 "--reply-file", reply]
        let b = ["-C", root.path, "suggest", "demo", "--from", "2026-06-10-handfix", "--from", "2026-06-09-slop",
                 "--reply-file", reply]
        #expect(try await SkilletHarness().run(a).exitCode == 0)
        let second = try await SkilletHarness().run(b)
        // The filename is order-independent, so identity must be too — otherwise the same draft is
        // reported as a different one occupying its own name.
        #expect(second.stdout.contains("this exact draft already exists"))
        #expect(!second.stdout.contains("a different draft already occupies"))
    }

    @Test("A broken shortcut beside a real record does not make it 'ambiguous'")
    func brokenShortcutDoesNotShadowRealRecord() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // Same id: a real finding, and a dangling shortcut in the sibling folder.
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("skills/demo/evaluations/friction/2026-06-09-slop.md"),
            withDestinationURL: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).md"))
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply])
        #expect(out.exitCode == 0, "the real record must be used, not blocked as ambiguous")
        #expect(!out.stderr.contains("ambiguous"))
    }

    @Test("A scratch folder the system won't let us write is the machine's problem, not our bug")
    func unwritableCacheIsEnvironmentNotInternal() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // Write the canned reply FIRST — denying writes would otherwise stop the fixture itself.
        let reply = try Self.writeReply(Self.goodReply, in: root)
        // Now deny writes on the project root so creating the scratch folder fails with a permissions error.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply])
        // Running as root defeats permission bits; only assert when the denial is real.
        if (try? FileManager.default.createDirectory(
                at: root.appendingPathComponent(".probe-\(UUID().uuidString)"),
                withIntermediateDirectories: false)) == nil {
            #expect(out.exitCode == 3, "a permissions failure is an environment problem")
            #expect(!out.stderr.contains("defect in skillet"))
            #expect(out.stderr.contains("permissions") || out.stderr.contains("could not write"))
        }
    }

    @Test("Editing the skill file makes it a different draft — identity follows the request, not just the ids")
    func changedSkillFileIsADifferentDraft() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let args = ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--out", "fix.json",
                    "--reply-file", reply]
        #expect(try await SkilletHarness().run(args).exitCode == 0)

        // Same evidence ids, but the skill file now differs — a materially different request, which used
        // to be reported as "you already drafted this" because only the ids were compared.
        let skillFile = root.appendingPathComponent("skills/demo/SKILL.md")
        let original = try String(contentsOf: skillFile, encoding: .utf8)
        try (original + "\nAn extra line that changes what gets sent.\n")
            .write(to: skillFile, atomically: true, encoding: .utf8)

        let second = try await SkilletHarness().run(args)
        #expect(second.stdout.contains("a different draft already occupies that name"))
        #expect(!second.stdout.contains("this exact draft already exists"))

        // Restoring the ORIGINAL file makes the request identical again, so it is the same draft.
        try original.write(to: skillFile, atomically: true, encoding: .utf8)
        #expect(try await SkilletHarness().run(args).stdout.contains("this exact draft already exists"))
    }

    @Test("A record is labelled by what it is, not by which folder it sat in")
    func recordLabelComesFromTheRecord() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // A hand-written note misfiled in the machine-mined folder: the label sent to the model must
        // still say what the record actually is.
        try "---\nschema: skillet.friction/1\nid: 2026-06-14-misfiled\nskill: demo\ndomain: demo\nlever: skill_md\nstate: logged\nsessions: [s1]\nskill_version: \"1.0\"\nmodel: opus\n---\nI hand-fixed this.\n"
            .write(to: root.appendingPathComponent("skills/demo/evaluations/findings/2026-06-14-misfiled.md"),
                   atomically: true, encoding: .utf8)
        let reply = try Self.writeReply(
            #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"x","rationale":"r","addresses":["2026-06-14-misfiled"]}]}"#,
            in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-14-misfiled", "--reply-file", reply])
        #expect(out.exitCode == 0)   // usable; only the label was ever at stake
    }

    @Test("A scratch folder that cannot be written refuses BEFORE paying, not after")
    func unwritableCacheRefusesBeforeSpending() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // A plain file where the scratch folder belongs. The canned reply stands in for the model call,
        // so reaching it would SUCCEED — meaning a failure here proves the layout was checked first.
        try "not a directory".write(to: root.appendingPathComponent(".skillet"),
                                    atomically: true, encoding: .utf8)
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply])
        #expect(out.exitCode == 4, "a broken layout is the project's problem")
        #expect(out.stderr.contains("a directory is expected"))
        // If the check ran after the call instead, this would have drafted successfully first.
        #expect(!out.stdout.contains("drafted"))
    }

    @Test("When nothing is written, the closing line says something true for that specific reason")
    func closingLineMatchesTheWriteOutcome() async throws {
        let root = try Self.makeRepo(friction: true); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let args = ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--out", "fix.json",
                    "--reply-file", reply]

        // Written: point at what was written.
        let first = try await SkilletHarness().run(args)
        #expect(first.stdout.contains("review the excerpt → proposed text in .skillet/proposals/fix.json"))

        // Identical draft already present: you are in the desired state — name the file worth reading.
        let repeated = try await SkilletHarness().run(args)
        #expect(repeated.stdout.contains("nothing to write — review the existing draft at .skillet/proposals/fix.json"))
        #expect(!repeated.stdout.contains("review the excerpt →"))

        // A different draft holds the name: the useful step is how to write yours.
        let reply2 = try Self.writeReply(
            #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"y","rationale":"r","addresses":["2026-06-10-handfix"]}]}"#,
            in: root, named: "reply2.json")
        let taken = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-10-handfix", "--out", "fix.json",
             "--reply-file", reply2])
        #expect(taken.stdout.contains("occupied by something else"))
        #expect(taken.stdout.contains("--out"))
        #expect(!taken.stdout.contains("review the excerpt →"))
    }

    @Test("A model program that runs but fails is described as such — never as 'could not find it'")
    func failedCallIsNotReportedAsMissing() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // A stand-in that exists, reports an acceptable version and a signed-in state, then fails the
        // actual call — the shape of a rate limit, a bad model name, or an expired credential.
        let shim = root.appendingPathComponent("claude-shim")
        try """
        #!/bin/sh
        case "$1" in
          --version) echo '9.9.9 (Claude Code)'; exit 0 ;;
          auth) echo '{"loggedIn": true}'; exit 0 ;;
          *) echo 'rate limit exceeded' >&2; exit 1 ;;
        esac
        """.write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim.path])
        #expect(out.exitCode == 3, "the harness is the obstacle — an environment problem")
        // The old message claimed the program was missing and told you to install it.
        #expect(!out.stderr.contains("could not find"))
        #expect(!out.stderr.contains("install claude-code"))
        #expect(out.stderr.contains("could not be used"))
    }

    @Test("A note belonging to another skill is not pulled in as context, and is reported")
    func foreignSkillNoteIsNotUsedAsContext() async throws {
        let root = try Self.makeRepo(friction: true); defer { Fixture.remove(root) }
        try "---\nschema: skillet.friction/1\nid: 2026-06-15-foreign\nskill: other-skill\ndomain: other-skill\nlever: skill_md\nstate: logged\nsessions: [s1]\nskill_version: \"1.0\"\nmodel: opus\n---\nAbout a different skill entirely.\n"
            .write(to: root.appendingPathComponent("skills/demo/evaluations/friction/2026-06-15-foreign.md"),
                   atomically: true, encoding: .utf8)
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("belongs to skill 'other-skill'"))
    }

    /// Covers the WIRING — that the folder scanner passes the record's own type through to the drafter.
    /// (What the drafter then prints is asserted directly in `AnalysisKitTests`.) Written as a size
    /// comparison because the assembled prompt is never printed anywhere, only measured: frontmatter does
    /// not enter the prompt and both runs use the same id, body and session, so the description of that
    /// record is the ONLY thing that can differ. A scanner that trusts the folder yields identical sizes.
    @Test("A finding misfiled under friction/ is described to the model as a finding, not as a note")
    func labelFollowsTheRecordNotTheFolder() async throws {
        func estimate(schemaLine: String, extraFields: String) async throws -> Int {
            let root = try Self.makeRepo(); defer { Fixture.remove(root) }
            // Same id, same body, same session as the named finding — only the record type differs.
            try "---\nschema: \(schemaLine)\nid: 2026-06-10-handfix\nskill: demo\ndomain: demo\nlever: skill_md\nstate: logged\nsessions: [s1]\nskill_version: \"1.0\"\nmodel: opus\n\(extraFields)---\nSame body either way.\n"
                .write(to: root.appendingPathComponent("skills/demo/evaluations/friction/2026-06-10-handfix.md"),
                       atomically: true, encoding: .utf8)
            let out = try await SkilletHarness().run(
                ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--dry-run", "--json"])
            #expect(out.exitCode == 0)
            let json = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any])
            return try #require(json["estimated_prompt_bytes"] as? Int)
        }
        let asNote = try await estimate(schemaLine: "skillet.friction/1", extraFields: "")
        let asFinding = try await estimate(schemaLine: "skillet.finding/1",
                                           extraFields: "source: scorer\nconfidence: high\n")
        #expect(asFinding != asNote,
                "the record's own type must change how it is described to the model")
    }

    // MARK: - the hidden test-only option

    @Test("The hidden reply option is refused outright unless the suite enabled it")
    func replyFileRefusedWhenSeamsDisabled() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply],
            environment: ["SKILLET_TEST_SEAMS": ""])          // empty counts as unset
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("--reply-file is a test-only option"))
    }

    /// The security regression. Unconfined, this read any regular file on the machine — and because an
    /// unparseable reply is quoted back in the error, it printed the first 200 bytes of whatever it was
    /// aimed at. Enabled here on purpose: the confinement must hold even for a legitimate test run.
    @Test("Even when enabled, the reply option cannot read outside the project — and echoes nothing")
    func replyFileCannotEscapeTheProject() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let elsewhere = try Fixture.makeTempDirectory(); defer { Fixture.remove(elsewhere) }
        let secret = elsewhere.appendingPathComponent("secret.txt")
        try "TOP-SECRET-CANARY-VALUE\n".write(to: secret, atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", secret.path])
        #expect(out.exitCode != 0)
        #expect(!out.stdout.contains("TOP-SECRET-CANARY-VALUE"))
        #expect(!out.stderr.contains("TOP-SECRET-CANARY-VALUE"),
                "no part of a file outside the project may be echoed back")
    }

    // MARK: - what the summary describes when nothing was written

    @Test("A repeat run describes the draft ON DISK, not the one it just generated and discarded")
    func repeatRunDescribesTheStoredDraft() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let one = try Self.writeReply(Self.goodReply, in: root, named: "one.json")
        // A second reply with TWO edits — models are not deterministic, so a re-run legitimately differs.
        let two = try Self.writeReply(
            ##"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"a","rationale":"r","addresses":["2026-06-09-slop"]},{"current_excerpt":"# Guide","proposed_text":"# Guidance","rationale":"r","addresses":["2026-06-09-slop"]}]}"##,
            in: root, named: "two.json")

        let first = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", one, "--json"])
        #expect(first.exitCode == 0)
        let firstJSON = try #require(try JSONSerialization.jsonObject(with: Data(first.stdout.utf8)) as? [String: Any])
        let storedPath = try #require(firstJSON["path"] as? String)

        let again = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", two, "--json"])
        #expect(again.exitCode == 0, "the draft you wanted exists — that is success")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(again.stdout.utf8)) as? [String: Any])
        #expect(json["edits"] as? Int == 1, "the file holds one edit; the discarded re-draft held two")
        #expect(json["path"] as? String == storedPath, "it must name the file it sends you to read")
        #expect(json["proposal_id"] as? String == firstJSON["proposal_id"] as? String)
    }

    @Test("When a different file holds the name, no draft is reported at all and the status says so")
    func blockedNameReportsNoDraft() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let proposals = root.appendingPathComponent(".skillet/proposals", isDirectory: true)
        try FileManager.default.createDirectory(at: proposals, withIntermediateDirectories: true)
        try #"{"schema":"skillet.proposal/1","id":"someone-elses","skill":"demo","motivation":[],"expected":[],"model":"m","prompt_version":"v1","request_fingerprint":"deadbeef","edits":[]}"#
            .write(to: proposals.appendingPathComponent("taken.json"), atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop",
             "--out", "taken.json", "--reply-file", reply, "--json"])
        #expect(out.exitCode == 2)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any])
        #expect(json["proposal_id"] is NSNull, "nothing of ours was saved, so there is no id to look up")
        #expect(json["path"] is NSNull)
        #expect(json["edits"] as? Int == 0)
        // What you ASKED for is still reported — only what a draft CONTAINS comes from a draft.
        #expect(json["motivation"] as? [String] == ["2026-06-09-slop"])
    }

    // MARK: - never write what cannot be read back

    @Test("An over-size file at the draft's name is reported as too large, not as corrupt")
    func oversizeOccupantIsNotCalledUnreadable() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let proposals = root.appendingPathComponent(".skillet/proposals", isDirectory: true)
        try FileManager.default.createDirectory(at: proposals, withIntermediateDirectories: true)
        // Above the draft read budget. Only a file swapped between runs can get here, since a reply is
        // capped well below it — but "could not be read" sent people looking for damage that isn't there.
        let big = String(repeating: "x", count: (5 << 20))
        try big.write(to: proposals.appendingPathComponent("taken.json"), atomically: true, encoding: .utf8)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop",
             "--out", "taken.json", "--reply-file", reply])
        #expect(out.exitCode == 2)
        #expect(out.stdout.contains("too large to check"))
        #expect(!out.stdout.contains("could not be read"))
    }

    /// The drafting call used to inherit the grader's 64 MiB output allowance — so it could return far
    /// more than the collision check would ever read back, and write a file it then called unreadable.
    @Test("A runaway reply fails the run instead of saving a draft that cannot be read back")
    func runawayReplyDoesNotLeaveAnUnreadableDraft() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let shim = root.appendingPathComponent("claude-shim")
        try """
        #!/bin/sh
        case "$1" in
          --version) echo '9.9.9 (Claude Code)'; exit 0 ;;
          auth) echo '{"loggedIn": true}'; exit 0 ;;
          *) awk 'BEGIN{
               printf "{\\"edits\\":[{\\"current_excerpt\\":\\"Always use the rule of three.\\",\\"proposed_text\\":\\"";
               for(i=0;i<600000;i++) printf "0123456789";
               printf "\\",\\"rationale\\":\\"r\\",\\"addresses\\":[\\"2026-06-09-slop\\"]}]}" }' ; exit 0 ;;
        esac
        """.write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop"],
            environment: ["SKILLET_CLAUDE_CODE_BIN": shim.path])
        // Valid JSON on purpose: a malformed blob would fail at parsing and prove nothing about the
        // size bound. This is a well-formed draft ~6 MB long — larger than the collision check can ever
        // read back, so without a bound on the reply it would be saved and then called unreadable.
        #expect(out.exitCode != 0, "a 6 MB draft is a runaway, not a minimal surgical edit")

        // The invariant that matters: nothing was left behind that a later run could not read.
        let proposals = root.appendingPathComponent(".skillet/proposals", isDirectory: true)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: proposals.path)) ?? [] {
            let size = (try? FileManager.default.attributesOfItem(
                atPath: proposals.appendingPathComponent(name).path)[.size] as? Int) ?? 0
            #expect(size < (4 << 20), "wrote \(name) at \(size) bytes — larger than it can read back")
        }
    }

    // MARK: - a saved draft's derived fields stay true

    /// The flow the command itself recommends: it closes by telling you to write an eval so the fix can
    /// be proven. Do that, come back, and the saved draft used to still claim no test covered it —
    /// because the test links are not part of what gets sent to the model, so the "same draft?" check
    /// could not see them change.
    @Test("Linking a test after drafting refreshes the saved draft instead of returning a stale one")
    func linkingAnEvalRefreshesTheSavedDraft() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let reply = try Self.writeReply(Self.goodReply, in: root)
        let record = root.appendingPathComponent("skills/demo/evaluations/findings/2026-06-09-slop.md")
        let args = ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop",
                    "--reply-file", reply, "--json"]

        let first = try await SkilletHarness().run(args)
        #expect(first.exitCode == 0)
        let firstJSON = try #require(try JSONSerialization.jsonObject(with: Data(first.stdout.utf8)) as? [String: Any])
        #expect((firstJSON["expected"] as? [String])?.isEmpty == true, "precondition: nothing linked yet")
        let savedPath = try #require(firstJSON["path"] as? String)

        // Now do exactly what the closing advice says: write an eval and link it to the record.
        let text = try String(contentsOf: record, encoding: .utf8)
        try text.replacingOccurrences(of: "model: opus", with: "model: opus\neval: rule-of-three-density")
            .write(to: record, atomically: true, encoding: .utf8)

        let again = try await SkilletHarness().run(args)
        #expect(again.exitCode == 0)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(again.stdout.utf8)) as? [String: Any])
        #expect(json["expected"] as? [String] == ["rule-of-three-density"],
                "the newly linked test must be reported, not the empty list from before")
        #expect((json["disclosures"] as? [[String: String]])?
            .contains { $0["reason"]?.contains("has been refreshed") == true } == true,
                "a write must never be silent")

        // And the file itself is true, not just the summary.
        let onDisk = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent(savedPath))) as? [String: Any])
        #expect(onDisk["expected"] as? [String] == ["rule-of-three-density"])
        #expect((onDisk["edits"] as? [[String: Any]])?.count == 1, "nothing else was disturbed")
    }

    @Test("A shortcut in the evidence folder is not offered as an id you could have named")
    func shortcutIsNotOfferedAsAvailable() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        let findings = root.appendingPathComponent("skills/demo/evaluations/findings", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: findings.appendingPathComponent("2026-06-20-linked.md"),
            withDestinationURL: findings.appendingPathComponent("2026-06-09-slop.md"))

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-01-01-nope"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("2026-06-09-slop"), "the real record is still offered")
        #expect(!out.stderr.contains("2026-06-20-linked"),
                "offering a shortcut hands over a choice that fails the moment it is taken")
    }

    /// The draft is created by writing a temporary neighbour and linking it into place, so the final
    /// name never holds a half-written file. The neighbour must not survive the write.
    @Test("A written draft leaves no leftover temporary file beside it")
    func writingLeavesNoDebris() async throws {
        let root = try Self.makeRepo(); defer { Fixture.remove(root) }
        // A deletion — the edit shape the instructions ask for — carried end to end into the file.
        let reply = try Self.writeReply(
            #"{"edits":[{"current_excerpt":"Always use the rule of three.","proposed_text":"","rationale":"dead prose","addresses":["2026-06-09-slop"]}]}"#,
            in: root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-slop", "--reply-file", reply, "--json"])
        #expect(out.exitCode == 0)

        let proposals = root.appendingPathComponent(".skillet/proposals", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(atPath: proposals.path)
        #expect(entries.count == 1, "found \(entries) — a temporary file was left behind")
        let saved = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: proposals.appendingPathComponent(entries[0]))) as? [String: Any])
        let edits = try #require(saved["edits"] as? [[String: Any]])
        #expect(edits.first?["proposed_text"] as? String == "", "the deletion reached the file")
    }
}
