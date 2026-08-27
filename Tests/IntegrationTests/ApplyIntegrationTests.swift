import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// F42 — putting a reviewed draft into the working tree. Every test is free: applying calls no model.
@Suite("skillet suggest --apply via the binary", .tags(.integration))
struct ApplyIntegrationTests {
    static let skillBody = """
    ---
    name: demo
    description: A demo skill for applying, long enough to satisfy the lint rules.
    ---
    # Guide

    Always use the rule of three.

    Keep replies short.

    """

    /// A repository with a committed skill and one saved draft. Returns the draft's filename.
    static func makeRepo(edits: String? = nil) async throws -> (root: URL, draft: String) {
        let root = try Fixture.makeTempDirectory()
        try await run("git", ["init", "-q"], in: root)
        try "project:\n  skills_root: skills\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        let skill = root.appendingPathComponent("skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try skillBody.write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let proposals = root.appendingPathComponent(".skillet/proposals", isDirectory: true)
        try FileManager.default.createDirectory(at: proposals, withIntermediateDirectories: true)
        try ".skillet is scratch\n*\n".write(
            to: root.appendingPathComponent(".skillet/.gitignore"), atomically: true, encoding: .utf8)

        let body = edits ?? #"""
        {"path":"SKILL.md","skill_md_lines":"7","current_excerpt":"Always use the rule of three.",
         "proposed_text":"Use three when it helps.","rationale":"absolute phrasing","addresses":[]}
        """#
        let draft = """
        {"schema":"skillet.proposal/1","id":"2026-08-02-demo-abcd1234","skill":"demo",
         "motivation":[],"expected":[],"model":"m","prompt_version":"v1",
         "request_fingerprint":"abcd1234","edits":[\(body)]}
        """
        try draft.write(to: proposals.appendingPathComponent("fix.json"), atomically: true, encoding: .utf8)

        try await run("git", ["add", "-A"], in: root)
        try await run("git", ["-c", "user.email=t@e", "-c", "user.name=t", "commit", "-qm", "base"], in: root)
        return (root, "fix.json")
    }

    /// Runs a helper program for test setup. Uses the project's one sanctioned launcher, which the
    /// charter requires without exception — this file was briefly the only place in the whole codebase
    /// reaching for the standard library's process API instead.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String], in directory: URL) async throws -> String {
        let result = try await Subprocess.run(
            .name(tool), arguments: .init(arguments),
            workingDirectory: FilePath(directory.path),
            output: .string(limit: 1 << 20), error: .string(limit: 1 << 20))
        return (result.standardOutput ?? "") + (result.standardError ?? "")
    }

    static func skillText(_ root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent("skills/demo/SKILL.md"), encoding: .utf8)
    }

    // MARK: - the happy path

    @Test("A clean repository and a valid draft: the file changes, exit 0")
    func appliesToWorkingTree() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 0)
        #expect(try Self.skillText(root).contains("Use three when it helps."))
        #expect(try !Self.skillText(root).contains("Always use the rule of three."))
    }

    /// The charter's absolute rule, asserted against the repository itself rather than trusted.
    @Test("Nothing is committed and nothing is staged")
    func neverCommitsNeverStages() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let before = try await Self.run("git", ["rev-parse", "HEAD"], in: root)
        _ = try await SkilletHarness().run(["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])

        #expect(try await Self.run("git", ["rev-parse", "HEAD"], in: root) == before, "a new commit was created")
        let staged = try await Self.run("git", ["diff", "--cached", "--name-only"], in: root)
        #expect(staged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "something was staged")
        let status = try await Self.run("git", ["status", "--porcelain"], in: root)
        #expect(status.contains(" M skills/demo/SKILL.md"), "the change should be unstaged and visible")
    }

    @Test("The machine-readable summary reports what was applied, and that nothing was committed")
    func machineSummary() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply", "--json"])
        #expect(out.exitCode == 0)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any])
        #expect(json["schema"] as? String == "skillet.apply/1")
        #expect(json["path"] as? String == "skills/demo/SKILL.md")
        #expect(json["applied"] as? [Int] == [0])
        #expect(json["committed"] as? Bool == false)
        #expect(json["proposal_id"] as? String == "2026-08-02-demo-abcd1234")
    }

    // MARK: - the refusals

    @Test("A repository with uncommitted changes is refused, and the skill file is untouched")
    func refusesDirtyRepository() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        try "scratch\n".write(to: root.appendingPathComponent("unrelated.txt"),
                              atomically: true, encoding: .utf8)
        let before = try Self.skillText(root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 5)
        #expect(out.stderr.contains("uncommitted changes"))
        #expect(try Self.skillText(root) == before, "nothing may be written when the check refuses")
    }

    /// All-or-nothing: a draft where one edit still matches and one has drifted must write neither.
    @Test("One drifted edit refuses the whole draft, leaving the file byte-identical")
    func driftRefusesEverything() async throws {
        let two = #"""
        {"path":"SKILL.md","skill_md_lines":"7","current_excerpt":"Keep replies short.",
         "proposed_text":"Be brief.","rationale":"r","addresses":[]},
        {"path":"SKILL.md","skill_md_lines":"9","current_excerpt":"A line nobody wrote",
         "proposed_text":"x","rationale":"r","addresses":[]}
        """#
        let (root, draft) = try await Self.makeRepo(edits: two); defer { Fixture.remove(root) }
        let before = try Self.skillText(root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 5)
        #expect(out.stderr.contains("no longer in the file"))
        #expect(try Self.skillText(root) == before,
                "the edit that would have applied must not be written either")
    }

    @Test("An edit number the draft does not have is a usage mistake, not a drift refusal")
    func unknownEditNumber() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply", "--edits", "7"])
        #expect(out.exitCode == 2)
        // Asserted on what the refusal must *carry* rather than on one phrasing: the flag that held the
        // mistake, and how many edits there actually are. The wording is shared with the proving command
        // now (Specs/020 D13) and human text carries no compatibility promise (design P7), so pinning a
        // sentence would break on a rewording that lost nothing.
        #expect(out.stderr.contains("--edits 7"), "names the flag that carried the mistake")
        #expect(out.stderr.contains("(it has 1)"), "and says how many edits the draft has")
    }

    @Test("A draft written for another skill is refused")
    func wrongSkill() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let path = root.appendingPathComponent(".skillet/proposals/\(draft)")
        let text = try String(contentsOf: path, encoding: .utf8)
        try text.replacingOccurrences(of: #""skill":"demo""#, with: #""skill":"other""#)
            .write(to: path, atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("drafted for"))
    }

    @Test("A malformed draft is reported as a bad file, not as a refusal")
    func malformedDraft() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        try "this is not a draft".write(
            to: root.appendingPathComponent(".skillet/proposals/\(draft)"),
            atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 4)
    }

    @Test("Outside a repository there is no way to undo, so applying is refused")
    func notARepository() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 3)
        #expect(out.stderr.contains("git"))
    }

    @Test("Asking to draft and to apply in one command is refused")
    func draftAndApplyTogether() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--from", "2026-06-09-x", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("two commands"))
    }

    @Test("Naming a draft without asking to apply it is refused rather than ignored")
    func proposalsWithoutApply() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("--apply"))
    }

    // MARK: - previewing (the flag that once wrote anyway)

    /// The bug this exists for: `--dry-run` was ignored in apply mode, so the file was written and the
    /// run reported success. Across this tool the flag means one thing — do the free work, say what
    /// would happen, change nothing.
    @Test("Previewing an apply writes nothing and says what would land")
    func previewWritesNothing() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let before = try Self.skillText(root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply", "--dry-run"])
        #expect(out.exitCode == 0, "a draft that would apply cleanly previews as success")
        #expect(try Self.skillText(root) == before, "a preview must never write")
        #expect(out.stdout.contains("would apply"))
        #expect(out.stdout.contains("nothing written"))
    }

    /// The status answers "would a real run succeed right now?", which is what makes it scriptable.
    @Test("A preview that would be refused exits with the refusal status, still writing nothing")
    func previewReportsRefusalStatus() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        try "scratch\n".write(to: root.appendingPathComponent("unrelated.txt"),
                               atomically: true, encoding: .utf8)
        let before = try Self.skillText(root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply", "--dry-run"])
        #expect(out.exitCode == 5)
        #expect(try Self.skillText(root) == before)
    }

    /// A run about to write must stop at the first refusal. A preview has no such constraint, and being
    /// told everything at once is the point of previewing.
    @Test("A preview reports every blocker, not just the first")
    func previewReportsEveryBlocker() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        // Two independent blockers: the repository is dirty, and the passage has moved on.
        try (Self.skillBody.replacingOccurrences(of: "Always use the rule of three.", with: "Something else."))
            .write(to: root.appendingPathComponent("skills/demo/SKILL.md"), atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply", "--dry-run"])
        #expect(out.exitCode == 5)
        #expect(out.stdout.contains("uncommitted changes"), "the dirty repository must be reported")
        #expect(out.stdout.contains("no longer in the file"), "the drifted edit must be reported too")
    }

    @Test("The machine-readable preview says plainly that it was a preview")
    func previewMachineSummary() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply", "--dry-run", "--json"])
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any])
        #expect(json["dry_run"] as? Bool == true)
        #expect(json["applied"] as? [Int] == [0], "which edits would land is still reported")
        #expect(json["committed"] as? Bool == false)
    }

    @Test("The command's own help no longer claims it applies nothing")
    func helpDescribesBothModes() async throws {
        let out = try await SkilletHarness().run(["suggest", "--help"])
        #expect(out.exitCode == 0)
        #expect(!out.stdout.contains("applies nothing"),
                "the help contradicted the --apply flag printed a few lines below it")
        #expect(out.stdout.contains("--apply"))
        #expect(out.stdout.lowercased().contains("never committed") || out.stdout.contains("commit is always yours"))
    }

    // MARK: - gaps worth closing

    /// The engine covers subset selection; nothing drove a *valid* subset through the command line.
    @Test("Applying a chosen subset writes those edits and leaves the others alone")
    func appliesChosenSubset() async throws {
        let two = #"""
        {"path":"SKILL.md","skill_md_lines":"7","current_excerpt":"Always use the rule of three.",
         "proposed_text":"FIRST","rationale":"r","addresses":[]},
        {"path":"SKILL.md","skill_md_lines":"9","current_excerpt":"Keep replies short.",
         "proposed_text":"SECOND","rationale":"r","addresses":[]}
        """#
        let (root, draft) = try await Self.makeRepo(edits: two); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply", "--edits", "1", "--json"])
        #expect(out.exitCode == 0)
        let text = try Self.skillText(root)
        #expect(text.contains("SECOND"), "the chosen edit lands")
        #expect(text.contains("Always use the rule of three."), "the unchosen edit is untouched")
        #expect(!text.contains("FIRST"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any])
        #expect(json["applied"] as? [Int] == [1], "the summary names which edit went in")
    }

    /// Permissions are set on the replacement *before* it goes into place, so the file at its real name
    /// never carries generic defaults — not even briefly, and not permanently if the process dies.
    @Test("A restrictive file keeps its permissions, and a permissive one keeps its own")
    func permissionsAreCarriedNotDefaulted() async throws {
        for mode in [0o600, 0o644, 0o640] {
            let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
            let file = root.appendingPathComponent("skills/demo/SKILL.md")
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
            let out = try await SkilletHarness().run(
                ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
            #expect(out.exitCode == 0)
            let after = try #require(
                FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
            #expect(after.int16Value == Int16(mode), "expected \(String(mode, radix: 8)), got \(String(after.intValue, radix: 8))")
            #expect(try Self.skillText(root).contains("Use three when it helps."))
        }
    }

    @Test("A draft naming a file this version does not write says so, and does not say to draft again")
    func unsupportedPathHasItsOwnAdvice() async throws {
        let body = #"""
        {"path":"references/extra.md","skill_md_lines":"1","current_excerpt":"anything",
         "proposed_text":"x","rationale":"r","addresses":[]}
        """#
        let (root, draft) = try await Self.makeRepo(edits: body); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 5)
        #expect(out.stderr.contains("does not write"))
        #expect(!out.stderr.contains("the file changed since this draft was made"),
                "re-drafting cannot help — this version only ever writes the skill file")
    }

    // MARK: - the safety check cannot be muted

    /// `status.showUntrackedFiles=no` is a setting people turn on to make version control faster. With
    /// it, the summary the tool relied on reported a clean tree while untracked work sat right there —
    /// and the tool overwrote a file that could not be brought back.
    @Test("A setting that hides untracked files cannot make the tool think the tree is clean")
    func speedSettingCannotHideUntrackedWork() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        _ = try await Self.run("git", ["config", "status.showUntrackedFiles", "no"], in: root)
        try "work in progress\n".write(to: root.appendingPathComponent("unrelated.txt"),
                                        atomically: true, encoding: .utf8)
        let before = try Self.skillText(root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 5, "untracked work must still block the write")
        #expect(try Self.skillText(root) == before)
    }

    /// Even with untracked files fully reported, a folder listed in the project's ignore file is
    /// invisible to that summary — so the file being replaced has to be asked about directly.
    @Test("A skill file version control has never seen is refused, because nothing could undo the change")
    func untrackedTargetIsRefused() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        // Remove the skill from version control while leaving it on disk, and hide it from status.
        _ = try await Self.run("git", ["rm", "--cached", "-r", "-q", "skills"], in: root)
        try "skills/\n".write(to: root.appendingPathComponent(".gitignore"),
                               atomically: true, encoding: .utf8)
        _ = try await Self.run("git", ["add", "-A"], in: root)
        _ = try await Self.run("git", ["-c", "user.email=t@e", "-c", "user.name=t", "commit", "-qm", "ignore"], in: root)
        let before = try Self.skillText(root)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 5)
        #expect(out.stderr.contains("not in version control"))
        #expect(out.stderr.contains("commit"), "the advice must say what to do")
        #expect(try Self.skillText(root) == before, "the file must survive")
    }

    /// A mistake in what you typed must be answered before anything about the state of your machine.
    /// The same typo used to give a clear answer on a clean working copy and an unrelated one otherwise,
    /// so you fixed the wrong thing and met the real mistake on a second run.
    @Test("An edit number that does not exist is reported even when the working copy is dirty")
    func badEditNumberBeatsTheWorkingCopyCheck() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        try "scratch\n".write(to: root.appendingPathComponent("unrelated.txt"),
                               atomically: true, encoding: .utf8)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply", "--edits", "7"])
        #expect(out.exitCode == 2, "the typo is the user's mistake and answers first")
        #expect(out.stderr.contains("--edits 7"), "and the answer is about the typo")
        #expect(!out.stderr.contains("uncommitted"), "the unrelated file must not mask the typo")
    }

    /// The write goes through a neighbouring file before being put into place. When it failed, the error
    /// named that neighbour — telling you that you lack permission on a randomly-named file you have
    /// never seen — and printed the whole error structure around it.
    /// **Skipped when the account can ignore permission bits**, which is the administrator account and
    /// therefore the container this project's checks run in. Unlike the other cases in this file, the
    /// thing under test *is* a refusal by the operating system, so there is no way to provoke it for a
    /// user who is never refused — and a test that silently proves nothing is worse than one that says
    /// it did not run.
    @Test("A refused write names the file you asked for, in plain words",
          .enabled(if: geteuid() != 0, "permission bits do not constrain the administrator account"))
    func writeFailureNamesTheRealFile() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let folder = root.appendingPathComponent("skills/demo")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 3)
        #expect(out.stderr.contains("skills/demo/SKILL.md"), "the file you asked to write")
        #expect(!out.stderr.contains(".replacing-"), "never the internal neighbour's name")
        #expect(!out.stderr.contains("UserInfo"), "the cause, not the whole error structure")
    }

    /// Naming the same edit twice reached the overlap check, which reported that edit 0 overlapped edit
    /// 0 — an edit cannot overlap itself — and advised applying them "one at a time with --edits", the
    /// very flag just used.
    @Test("Naming the same edit twice is reported as a mistake in the command")
    func repeatedEditNumberIsAMistake() async throws {
        let two = #"""
        {"path":"SKILL.md","skill_md_lines":"7","current_excerpt":"Always use the rule of three.",
         "proposed_text":"A","rationale":"r","addresses":[]},
        {"path":"SKILL.md","skill_md_lines":"9","current_excerpt":"Keep replies short.",
         "proposed_text":"B","rationale":"r","addresses":[]}
        """#
        let (root, draft) = try await Self.makeRepo(edits: two); defer { Fixture.remove(root) }
        let before = try Self.skillText(root)
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply", "--edits", "0", "0"])
        #expect(out.exitCode == 2, "a slip in the command, not a refusal by a safety check")
        #expect(out.stderr.contains("more than once"))
        #expect(!out.stderr.contains("overlapping"), "an edit cannot overlap itself")
        #expect(try Self.skillText(root) == before)
    }

    /// A replacement carrying Windows line breaks was written into a plain file unchanged, leaving the
    /// file mixing both conventions — visible as stray characters in some editors and noisy in diffs.
    @Test("A replacement never leaves the file mixing two line-break conventions")
    func replacementDoesNotMixLineBreaks() async throws {
        let windowsReplacement = #"""
        {"path":"SKILL.md","skill_md_lines":"7","current_excerpt":"Always use the rule of three.",
         "proposed_text":"Be brief.\r\nStay brief.","rationale":"r","addresses":[]}
        """#
        let (root, draft) = try await Self.makeRepo(edits: windowsReplacement); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 0)
        let written = try Data(contentsOf: root.appendingPathComponent("skills/demo/SKILL.md"))
        #expect(!written.contains([0x0D]), "the file uses plain line breaks and must stay that way")
        #expect(try Self.skillText(root).contains("Be brief.\nStay brief."))
    }

    /// Being unable to *find out* whether a file is in version control is a third outcome, distinct from
    /// finding out that it is not. It used to be reported as the latter — telling you to commit a file
    /// that may well already be committed — because any failure to run the check was read as an answer.
    @Test("A version-control check that cannot run says so, rather than claiming the file is untracked")
    func unrunnableCheckIsNotAnAnswer() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        // A stand-in that behaves like real version control except for the one query this check makes.
        // It is kept **outside** the project on purpose: a stray file inside it would be uncommitted work,
        // which the earlier clean-tree gate would refuse first, and this test would pass without ever
        // reaching the code it exists to cover.
        let elsewhere = try Fixture.makeTempDirectory(); defer { Fixture.remove(elsewhere) }
        let realGit = try await Self.run("sh", ["-c", "command -v git"], in: root)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shim = elsewhere.appendingPathComponent("git-shim")
        try """
        #!/bin/sh
        if [ "$1" = "ls-files" ]; then echo 'fatal: unable to read index file' >&2; exit 128; fi
        exec \(realGit) "$@"
        """.write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let before = try Self.skillText(root)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"],
            environment: ["SKILLET_GIT_BIN": shim.path])
        #expect(out.exitCode == 3, "the tool could not run its check — a problem with the machine, not a refusal")
        #expect(out.stderr.contains("is unknown"), "say the answer was not established")
        #expect(!out.stderr.contains("is not in version control"),
                "never assert something the check never determined")
        #expect(try Self.skillText(root) == before, "and still write nothing")
        #expect(!out.stderr.contains("signed in"), "advise about the program that actually failed")
    }

    /// Advice has to fit the program that failed. Every version-control failure used to end with "check
    /// you are signed in, that you are within any usage limits, and that the configured model name is
    /// valid" — advice for the paid model, printed when git was the problem, which sends you to look
    /// where the problem is not.
    @Test("Being outside a repository is explained as a version-control problem, not a sign-in one")
    func versionControlFailureGivesVersionControlAdvice() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        // Remove the repository itself; everything else about the project stays valid.
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 3, "no repository is a problem with the surroundings, not the command")
        #expect(out.stderr.contains("not inside a git repository"), "name the actual obstacle")
        #expect(out.stderr.contains("git status"), "hand over the command whose output says why")
        #expect(!out.stderr.contains("signed in") && !out.stderr.contains("model name"),
                "never offer advice about the model when the model was never involved")
    }

    /// Running out of time and never starting are different problems with different fixes, and they used
    /// to print the same sentence. The documented trap is the reverse of this — a program that could not
    /// start reported as a timeout — which sends you tuning limits on something that was never going to
    /// run. The time limit is lowered here so the test costs a second rather than two minutes.
    @Test("Running out of time says so, and points at the setting that raises the limit")
    func timeLimitIsItsOwnAnswer() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let elsewhere = try Fixture.makeTempDirectory(); defer { Fixture.remove(elsewhere) }
        let slow = elsewhere.appendingPathComponent("slow-git")
        try "#!/bin/sh\nsleep 3\n".write(to: slow, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slow.path)
        let before = try Self.skillText(root)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"],
            environment: ["SKILLET_GIT_BIN": slow.path, "SKILLET_GIT_TIMEOUT_SECONDS": "1"])
        #expect(out.exitCode == 3)
        #expect(out.stderr.contains("took longer than 1s"), "name the limit that was actually applied")
        #expect(out.stderr.contains("SKILLET_GIT_TIMEOUT_SECONDS"),
                "a limit you cannot raise is a dead end — name the way out in the message itself")
        #expect(!out.stderr.contains("could not be run"), "do not report this as a program that never started")
        #expect(try Self.skillText(root) == before)
    }

    /// The other half of the pair: a program that cannot start must not be dressed up as a time limit,
    /// and the reason should be the system's own words rather than a sentence written in advance. Asking
    /// such errors for a "localized description" yields the placeholder "The operation couldn't be
    /// completed", which names nothing.
    @Test("A program that cannot start reports what the system said, not a time limit")
    func launchFailureCarriesTheSystemsWords() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let elsewhere = try Fixture.makeTempDirectory(); defer { Fixture.remove(elsewhere) }
        let broken = elsewhere.appendingPathComponent("not-runnable")
        try "this is not a program".write(to: broken, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: broken.path)
        let before = try Self.skillText(root)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"],
            environment: ["SKILLET_GIT_BIN": broken.path])
        #expect(out.exitCode == 3)
        #expect(out.stderr.contains("could not be run"))
        #expect(out.stderr.contains("not-runnable"), "the system names the file it could not run — keep that")
        #expect(!out.stderr.contains("took longer"), "nothing timed out here")
        #expect(!out.stderr.contains("couldn’t be completed"),
                "the placeholder text that appears when an error carries no real description")
        #expect(try Self.skillText(root) == before)
    }

    /// Both jobs share one naming rule, so one function checks it — but the message named `--out` even
    /// when you had typed `--proposals`, sending you to look at a flag you never used.
    @Test("A bad draft name names the flag you actually typed")
    func rejectionNamesTheFlagYouTyped() async throws {
        let (root, _) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", "badname", "--apply"])
        #expect(out.exitCode == 2, "a mistake in what you typed")
        #expect(out.stderr.contains("--proposals 'badname'"))
        #expect(!out.stderr.contains("--out"), "never name a flag the command line did not contain")
    }

    /// A skill file written on a Mac before 2001 ends each line with a carriage return alone. Every
    /// passage spanning two lines used to fail to match, and the refusal said "the file changed since
    /// this draft was made; draft again" — the file had not changed, and drafting again hit the same
    /// wall. Reproduced through the command, not a stand-in: drafting refuses such a file earlier for an
    /// unrelated reason, so only a hand-written draft reaches here, which the format expressly allows.
    @Test("A skill file using carriage returns alone applies, and keeps its own line endings")
    func appliesToCarriageReturnFile() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let file = root.appendingPathComponent("skills/demo/SKILL.md")
        let asCarriageReturns = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "\n", with: "\r")
        try asCarriageReturns.write(to: file, atomically: true, encoding: .utf8)
        try await Self.run("git", ["add", "-A"], in: root)
        try await Self.run("git", ["-c", "user.email=t@e", "-c", "user.name=t", "commit", "-qm", "cr"], in: root)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 0, "a plain-newline draft must still match a carriage-return file")
        let after = try Self.skillText(root)
        #expect(after.contains("Use three when it helps."))
        #expect(!after.contains("\n"), "the file must not come back using two conventions at once")
    }

    /// The reported case, end to end. A skill file holding one carriage return among plain newlines used
    /// to be refused with "this edit has Windows line endings and the file does not" — the edit had plain
    /// newlines and the file was the one with the carriage return, so both halves were backwards, and the
    /// remedy told you to re-save the draft with plain line endings, which it already had.
    @Test("A file mixing line-break conventions blames the file, and names what it found")
    func mixedFileNamesWhatItFound() async throws {
        // A passage spanning two lines: a single-line one has no line break to disagree about, so it
        // matches whatever the file's conventions are and never reaches this refusal at all.
        let spanning = #"""
        {"path":"SKILL.md","skill_md_lines":"7-9","current_excerpt":"Always use the rule of three.\n\nKeep replies short.",
         "proposed_text":"Be brief.","rationale":"r","addresses":[]}
        """#
        let (root, draft) = try await Self.makeRepo(edits: spanning); defer { Fixture.remove(root) }
        let file = root.appendingPathComponent("skills/demo/SKILL.md")
        // One carriage return among plain newlines, and **not** immediately before one — a carriage
        // return placed just before an existing newline forms the Windows pair instead, which is a
        // different case entirely. (My first version of this fixture did exactly that.)
        try (String(contentsOf: file, encoding: .utf8) + "Footnote.\rAnd more.\n")
            .write(to: file, atomically: true, encoding: .utf8)
        try await Self.run("git", ["add", "-A"], in: root)
        try await Self.run("git", ["-c", "user.email=t@e", "-c", "user.name=t", "commit", "-qm", "mix"], in: root)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        #expect(out.exitCode == 5)
        #expect(out.stderr.contains("mixes line-break conventions"), "blame the file, which is the inconsistent one")
        #expect(out.stderr.contains("classic Mac") && out.stderr.contains("Unix"),
                "name both conventions actually present, so there is something to look for")
        #expect(!out.stderr.contains("this edit has Windows line endings"),
                "the edit has plain newlines; saying otherwise sends you to fix something that is already right")
        #expect(out.stderr.contains("convert"), "the remedy must be one that changes something")
    }

    /// A name that is nothing but the file extension names nothing you could pick out of a folder
    /// listing, and a name holding a space breaks the very command this tool prints for you to paste —
    /// the shell reads it as two arguments. Hidden names stay allowed: an earlier round removed a blanket
    /// leading-dot rejection on purpose, so this narrows that rather than undoing it.
    @Test("Draft names that name nothing, or contain a space, are refused",
          arguments: [(".json", "has no name before .json"),
                      ("...json", "has no name before .json"),
                      (" x.json", "must not contain spaces"),
                      ("a b.json", "must not contain spaces")])
    func meaninglessDraftNamesAreRefused(_ name: String, _ says: String) async throws {
        let (root, _) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", name, "--apply"])
        #expect(out.exitCode == 2, "a mistake in what you typed")
        #expect(out.stderr.contains(says), "say which rule it broke")
    }

    /// **A draft name starting with a hyphen is refused, for the same reason a space is.** The name is
    /// handed back inside `--proposals <name>`, and a value beginning with a hyphen is taken for the next
    /// switch — measured, the spaced form fails with "Missing value for '--proposals'" before the command
    /// starts. It has to be passed joined by `=` to reach the name rule at all, which is also the only way
    /// such a name could have been created in the first place.
    @Test("A draft name starting with a hyphen is refused", arguments: ["-x.json", "--out.json"])
    func hyphenLeadingDraftNameRefused(_ name: String) async throws {
        let (root, _) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals=\(name)", "--apply"])
        #expect(out.exitCode == 2, "a mistake in what you typed")
        #expect(out.stderr.contains("must not start with a hyphen"), "say which rule it broke")
    }

    /// The spaced form never even reaches the rule above — the argument reader refuses it first. Recorded
    /// so the two routes are not confused: closing only the reachable one would leave the rule untested.
    @Test("The spaced form is refused by the argument reader before the name rule is reached")
    func hyphenLeadingDraftNameRefusedEarlier() async throws {
        let (root, _) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", "-x.json", "--apply"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("Missing value"))
    }

    @Test("A hidden draft name is still allowed")
    func hiddenDraftNameStillWorks() async throws {
        let (root, _) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", ".draft.json", "--apply"])
        // It gets past the name rule and fails on the file not being there, which is the point.
        #expect(out.exitCode != 2, "a leading dot is a real name, refused on purpose only when nothing follows it")
        #expect(out.stderr.contains("not found"))
    }

    /// A rejection for a path that points somewhere else on disk used to end with "fix or regenerate the
    /// file so it matches its schema" — advice about the shape of a file's contents, for a problem that
    /// has no file and no schema. Advice for the wrong problem sends you looking where the problem is not.
    @Test("A path rejected for pointing elsewhere is told to fix the link, not a schema")
    func linkRefusalAdvisesAboutTheLink() async throws {
        let (root, draft) = try await Self.makeRepo(); defer { Fixture.remove(root) }
        let elsewhere = try Fixture.makeTempDirectory(); defer { Fixture.remove(elsewhere) }
        let proposals = root.appendingPathComponent(".skillet/proposals")
        try FileManager.default.removeItem(at: proposals)
        try FileManager.default.createSymbolicLink(at: proposals, withDestinationURL: elsewhere)

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "demo", "--proposals", draft, "--apply"])
        // The read refuses before the folder check gets there, so this asserts that refusal's wording,
        // not the folder check's — which is the point: several different rejections share one error and
        // therefore shared one piece of advice.
        #expect(out.stderr.contains("escapes its base directory"), "say what was rejected")
        #expect(out.stderr.contains("replace the symbolic link"), "and what to actually do about it")
        #expect(!out.stderr.contains("matches its schema"),
                "never advise editing a file's contents when no file's contents are wrong")
    }
}
