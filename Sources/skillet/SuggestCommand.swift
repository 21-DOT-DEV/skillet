import ArgumentParser
import Foundation
import EDDCore
import AnalysisKit
import ConfigYAML
import ProjectKit
import RenderKit
import JudgeKit
import RunKit
import HarnessKit

/// `skillet suggest` — the Suggest step (design §6.1, F41). Drafts a *minimal, surgical* edit to a
/// skill's `SKILL.md` from evidence you name, writing a content-anchored proposal set to
/// `.skillet/proposals/`. **Nothing is applied and nothing is committed** — applying (F42) and proving
/// by A/B (F43) are separate, later commands.
struct SuggestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "suggest",
        abstract: "Draft a minimal SKILL.md edit from observed evidence (writes a proposal; applies nothing).",
        discussion: """
        Reads the evidence you name — machine-mined findings and/or hand-written friction notes under \
        <skills-root>/<skill>/evaluations/ — pulls in friction that shares a session, and asks the model \
        for a minimal surgical edit anchored to text that appears exactly once in SKILL.md. The draft is \
        written to .skillet/proposals/ for you to review. Nothing is applied; the commit is always yours. \
        Use --dry-run to see exactly what would be sent, and what it would cost, without spending.
        """
    )

    /// The assembled prompt may not exceed this. A built-in constant, not a setting: nothing has asked to
    /// tune it, and `--yes` is the per-run escape hatch (Specs/018 D5/D8).
    static let promptCeilingBytes = 256 * 1024
    static let evidenceCap = 1 << 20

    /// What one drafting reply may return. **Not inherited from the grader**, whose reply is a short
    /// verdict and which therefore allows 64 MiB — drafting writes its reply to a file and must be able
    /// to read that file back. The request itself is already capped at ``promptCeilingBytes``, and a
    /// draft quotes passages out of that request, so a legitimate one is far smaller than this; anything
    /// larger is a runaway reply, and a multi-megabyte "minimal, surgical edit" is not usable output.
    static let replyCap = 1 << 20

    /// What we will read back from a saved draft. **Deliberately above ``replyCap``**, so the read side
    /// can never be the constraint that fails first on a file we wrote ourselves. Still bounded: the file
    /// may have been replaced by anything between runs, so it is untrusted at read time like any other.
    static let draftCap = 4 << 20

    @OptionGroup var options: GlobalOptions

    @Argument(help: "The skill to draft an edit for (exactly one).")
    var skill: String

    @Option(name: .long, parsing: .singleValue,
            help: "Evidence id to draft from — a finding or a friction note. Repeatable; at least one required.")
    var from: [String] = []

    @Option(name: .long, help: "Filename inside .skillet/proposals/ (must end in .json).")
    var out: String?

    @Flag(name: [.customShort("n"), .long], help: "Show what would be sent and what it would cost; spend nothing.")
    var dryRun = false

    @Flag(name: .long, help: "Proceed even though the estimated prompt exceeds the size ceiling.")
    var yes = false

    @Option(name: .customLong("reply-file"),
            help: ArgumentHelp("Test-only: read the model reply from a file instead of calling the model.",
                               visibility: .private))
    var replyFile: String?

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            try await draft(renderer: renderer)
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        } catch let error as SilentExit {
            throw error
        } catch {
            // Anything still unrecognised here is, by definition, something we did not anticipate — so
            // say that, instead of asserting a cause we cannot know. The previous version labelled every
            // such error "a problem with the drafts folder", which turned an unclassified failure into a
            // confidently wrong one (a model timeout was reported as bad user data). Blaming the user's
            // setup for our own defect is the same mistake in a nicer suit.
            let classified = EDDError.internalError(detail: "\(error)")
            Console.emit(renderer.renderError(classified))
            throw SilentExit(code: classified.exitCode.rawValue)
        }
    }

    private func draft(renderer: Renderer) async throws {
        // Before anything else: a hidden option is refused outright unless the suite enabled it.
        if replyFile != nil { try TestSeam.assertEnabled("--reply-file") }
        guard !from.isEmpty else {
            throw EDDError.usage(message: "no evidence named",
                                 remedy: "pass --from <evidence-id> (repeatable) — drafting only ever works from observed evidence")
        }
        if let out { try Self.validateOutName(out) }

        // ---- free, pre-spend: locate, confine, lint, resolve the model ------------------------------
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
        guard let root = context.root.map({ URL(fileURLWithPath: $0) }) else {
            throw EDDError.projectNotFound(cwd: context.cwd)
        }
        let config = try loadConfig(options: options, context: context)
        let skillsRoot = config?.project?.skillsRoot ?? "skills"
        let discovered = SkillScanner().scan(skillsRoot: root.appendingPathComponent(skillsRoot))
        // Exactly one skill: the shared selector returns *every* discovered skill for an empty list, so
        // the argument is required and passed as a single-element array (A20).
        let selected = try selectSkillDirectories(discovered, requested: [skill], command: "suggest")
        guard let discoveredDir = selected.first else {
            throw EDDError.usage(message: "unknown skill '\(skill)'", remedy: "skillet lint  # lists discovered skills")
        }
        // Rebuild lexically under the project root and confine before any read (A10) — the safe reader
        // alone does not prove a path stays inside the project.
        let skillDir = root.appendingPathComponent(skillsRoot).appendingPathComponent(discoveredDir.lastPathComponent)
        try TriageCommand.assertConfined(skillDir: skillDir, projectRoot: root, skill: skill)

        // Free before paid — in no-behavioral-tests mode, so a skill without an evals file isn't refused
        // for lacking one (A5); `suggest` runs no evals at all.
        // The same read serves both: the free gate above and the prompt below. Reading twice risked
        // linting one version of the file and drafting against another.
        let raw = try runFreeLintGate(skillDir: skillDir, lintConfig: config?.lint ?? .init(),
                                      renderer: renderer, behavioralAxisRuns: false)

        let (model, borrowed) = try Self.resolveModel(
            suggest: config?.suggest, config: config)

        // ---- evidence ------------------------------------------------------------------------------
        let evaluations = skillDir.appendingPathComponent("evaluations")
        // Naming the same id twice would load it twice, print it twice in the request (inflating size and
        // cost), and — since the identity fingerprint covers this list — yield a different filename for
        // what is really the same draft. De-duplicate, keeping first-mention order.
        var seen = Set<String>()
        let motivation = from.filter { seen.insert($0).inserted }
        var named: [DraftEvidence] = []
        for id in motivation {
            named.append(try Self.loadEvidence(id: id, skill: skill, skillDir: skillDir))
        }
        var frictionDisclosures: [Disclosure] = []
        let allFriction = Self.scanFriction(evaluations.appendingPathComponent("friction"), skill: skill, disclosures: &frictionDisclosures)
        let sessions = Set(named.flatMap(\.sessions))
        let linked = ProposalDrafter.linkedFriction(
            sessions: sessions, friction: allFriction, excluding: Set(named.map(\.id)))

        // ---- prompt, estimate, ceiling --------------------------------------------------------------
        let draftContext = DraftContext(
            skill: skill, skillMarkdown: raw.markdown, named: named, linkedFriction: linked,
            model: model, runDate: TriageCommand.dateStamp(now: Date()))
        let prompt = ProposalDrafter.prompt(draftContext)
        let estimate = prompt.utf8.count
        let expected = ProposalDrafter.expected(from: named)

        let overCeiling = estimate > Self.promptCeilingBytes

        // A preview always previews. The size limit guards **spending**, and a preview spends nothing —
        // refusing here denied the one case where looking first matters most: seeing how big an oversized
        // request actually is. It still says the request is over the limit, so the later refusal on a real
        // run is never a surprise.
        if dryRun {
            var previewNotes = frictionDisclosures
            if overCeiling {
                previewNotes.append(Disclosure(
                    subject: "prompt size",
                    reason: "\(estimate) bytes is over the \(Self.promptCeilingBytes)-byte ceiling — a real run needs --yes, or name fewer records"))
            }
            Console.emit(try renderer.renderSuggest(
                SuggestResult(skill: skill, proposalId: nil, path: nil, edits: 0,
                              motivation: motivation, expected: expected, model: model,
                              promptVersion: ProposalDrafter.promptVersion,
                              estimatedPromptBytes: estimate, dryRun: true, disclosures: previewNotes),
                nextSteps: ["re-run without --dry-run to draft"]))
            return
        }

        if overCeiling, !yes {
            throw EDDError.gate(
                message: "the assembled prompt is \(estimate) bytes — over the \(Self.promptCeilingBytes)-byte ceiling",
                remedy: "narrow --from to fewer records, re-run with --yes to spend anyway, or use --dry-run to inspect it first")
        }

        // The pre-spend sequence, cheapest and least invasive first: refuse a known-bad or signed-out
        // model program (read-only) BEFORE touching the filesystem, so a blocked harness leaves nothing
        // behind. Skipped when a canned reply stands in, because that spends nothing.
        if replyFile == nil {
            try await SpendGate.assertHarnessReady(
                ClaudeCodeAdapter(configPath: config?.harness?.claudeCode?.path))
        }

        // Prove the result can be SAVED before paying for it. Preparing the scratch folder is free and
        // safe to do early (it only creates the folder and its ignore file), so a broken layout — a plain
        // file where the folder belongs, a redirected path, no write permission — now refuses for nothing
        // instead of after the model has been paid. This is the ordering the measured-run command already
        // uses, and the same fail-before-you-spend rule as the free checks and the harness gate above.
        let proposalsDir = try CacheSupport.prepareCacheDirectory(projectRoot: root, subdirectory: "proposals")

        // ---- the one model call ---------------------------------------------------------------------
        let reply = try await Self.ask(prompt: prompt, model: model, config: config,
                                       replyFile: replyFile, projectRoot: root)
        let parsed: ParsedDraft
        do {
            parsed = try ProposalDrafter.parse(reply: reply, context: draftContext)
        } catch let error as DraftParseError {
            throw EDDError.invalidArtifact(
                path: "model reply",
                reason: "could not be read as a draft — got: \(error.excerpt)")
        }

        // ---- assemble + write ------------------------------------------------------------------------
        let requestFingerprint = ProposalDrafter.requestFingerprint(prompt: prompt, model: model)
        let setId = ProposalDrafter.setId(runDate: draftContext.runDate, skill: skill,
                                          requestFingerprint: requestFingerprint)
        // Stored **sorted** so the saved file is canonical: the filename already sorts before
        // fingerprinting, so listing the same records in another order produced the same name but a
        // different stored list — and the "same draft?" comparison then called it a different draft,
        // contradicting the rule stated beside it. The request sent to the model keeps the typed order.
        let set = ProposalSet(id: setId, skill: skill, motivation: motivation.sorted(), expected: expected,
                              model: model, promptVersion: ProposalDrafter.promptVersion,
                              requestFingerprint: requestFingerprint, edits: parsed.edits)
        var disclosures = frictionDisclosures + parsed.disclosures
        let outcome = try Self.write(set, named: out ?? "\(setId).json", proposals: proposalsDir,
                                     projectRoot: root, disclosures: &disclosures)

        // The three no-write situations are genuinely different, so say something different about each.
        // Repeating "review the proposal" when nothing was written contradicted the explanation printed
        // directly above it, and named no file to review.
        //
        // **Every fact about a draft is read back from the file that holds it.** The promise this summary
        // makes is "the file is the truth and I name it"; describing the draft just generated while
        // pointing at a different file is the one contradiction that promise exists to prevent.
        var steps: [String]
        let reported: ProposalSet?    // the draft that EXISTS — nil when none does
        let written: String?
        var requestBlocked = false
        switch outcome {
        case let .written(path):
            reported = set
            written = path
            steps = ["review the excerpt → proposed text in \(path)"]
        case let .identicalDraftExists(path, existing):
            // You are already in the desired state, and the file worth reading is right there — so it is
            // that file being described. Two things genuinely drift here: a re-run's reply can contain a
            // different number of edits (models are not deterministic), and the evals named come from a
            // record field that is not part of what makes two requests count as identical.
            reported = existing
            written = path
            steps = ["nothing to write — review the existing draft at \(path)"]
        case let .nameTaken(path):
            // Nothing of ours exists anywhere, so there is no draft to describe. Reporting an id for a
            // draft that was never saved invites a reader to look it up and find nothing.
            reported = nil
            written = nil
            requestBlocked = true
            steps = ["\(path) is occupied by something else — re-run with --out <name>.json to write this draft"]
        }
        if expected.isEmpty {
            steps.append("no eval covers this evidence yet — write one so the fix can be proven")
        }
        if borrowed { steps.append("drafted with the grading model — set suggest.model to choose another") }
        Console.emit(try renderer.renderSuggest(
            SuggestResult(skill: skill,
                          proposalId: reported?.id,
                          path: written,
                          edits: reported?.edits.count ?? 0,
                          // What you ASKED for stays yours even when nothing was saved; what a draft
                          // CONTAINS comes from the draft.
                          motivation: reported?.motivation ?? motivation,
                          expected: reported?.expected ?? expected,
                          model: reported?.model ?? model,
                          promptVersion: reported?.promptVersion ?? ProposalDrafter.promptVersion,
                          estimatedPromptBytes: estimate, dryRun: false, disclosures: disclosures),
            nextSteps: steps))
        // Printed first, then the status: you asked for a draft and got none, so reporting success would
        // let a script carry on as though one existed. The already-present matching draft is NOT this
        // case — there the state you wanted does exist, which is success by any reading.
        if requestBlocked { throw SilentExit(code: ExitCode.usage.rawValue) }
    }

    // MARK: - model resolution (D8/D9)

    /// `suggest.model` → `judge.model` → refuse. The grading **service** setting gates only the borrowed
    /// value: an explicitly-set drafting model has no service setting to contradict, while a borrowed
    /// grading model is only meaningful if that service is the one implemented. Returns whether it was
    /// borrowed, so the output can say so rather than falling back invisibly.
    static func resolveModel(suggest: SkilletConfig.Suggest?, config: SkilletConfig?) throws -> (model: String, borrowed: Bool) {
        if let own = suggest?.model?.trimmingCharacters(in: .whitespaces), !own.isEmpty {
            return (own, false)
        }
        let judge = config?.judge
        guard (judge?.provider ?? "claude-code") == "claude-code" else {
            throw EDDError.usage(
                message: "no suggest.model is set, and judge.model belongs to judge.provider '\(judge?.provider ?? "")' — a different service",
                remedy: "set `model:` under `suggest:` in skillet.yaml (drafting shells the claude CLI)")
        }
        guard let borrowed = judge?.model?.trimmingCharacters(in: .whitespaces), !borrowed.isEmpty else {
            throw EDDError.usage(
                message: "no drafting model is set — a paid draft needs an explicit model so results are reproducible",
                remedy: "add `model:` under `suggest:` (or under `judge:`) in skillet.yaml")
        }
        return (borrowed, true)
    }

    /// The single one-shot call. The test seam substitutes a canned reply and never resolves a binary —
    /// so every test is $0 and no test can reach the network (A6).
    static func ask(prompt: String, model: String, config: SkilletConfig?, replyFile: String?,
                    projectRoot: URL) async throws -> String {
        if let replyFile {
            // **Confined to the project.** Unconfined, this read any regular file on the machine — and
            // an unparseable reply is quoted back in the error, so it printed the first 200 bytes of
            // whatever it was aimed at. Quoting a real model reply stays: that is the model's own output
            // and it makes a failure diagnosable without paying twice.
            switch SafeFile.readConfinedRegularText(URL(fileURLWithPath: replyFile),
                                                    base: projectRoot, cap: evidenceCap) {
            case let .success(text): return text
            case let .failure(refusal):
                throw EDDError.invalidArtifact(path: replyFile, reason: "canned reply \(refusal.reason)")
            }
        }
        guard let resolved = BinaryResolver().resolve(
            flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN",
            configPath: config?.harness?.claudeCode?.path, pathName: "claude") else {
            throw EDDError.harnessNotFound(harness: "claude-code", reason: nil)
        }
        do {
            return try await ClaudeCLIJudgeRunner(binaryPath: resolved.path, outputLimitBytes: replyCap)
                .ask(prompt: prompt, model: model)
        } catch let error as JudgeRunnerError {
            // A resolved program that exits non-zero (auth, rate limit, unknown model) is infrastructure,
            // not a graded result — `suggest` runs no trials, so there is nothing to grade (A7).
            guard case let .failed(code, stderr) = error else { throw error }
            throw EDDError.harnessNotFound(
                harness: "claude-code",
                reason: "the program exited with status \(code): \(stderr.prefix(200))")
        } catch {
            // Everything else from this one call is, by definition, a failure to run the model program:
            // a timeout, or a launch error from the subprocess library (an unexecutable path throws its
            // own error type, not the launcher's — which is why narrowing by error *type* was wrong and
            // narrowing by *call site* is right). The scope here is a single operation whose failure mode
            // is unambiguous, so classifying it as infrastructure asserts nothing we don't know.
            throw EDDError.harnessNotFound(harness: "claude-code", reason: "\(error)")
        }
    }

    // MARK: - evidence

    /// Resolve one named id: findings first, then friction. "Absent here" is a plain miss, never a
    /// disclosure; absent from both is misuse; present in both is refused as ambiguous rather than
    /// silently resolved by order. A named record that resolves but cannot be read or decoded is fatal
    /// (A17) — skipping it would draft from incomplete evidence while reporting success.
    static func loadEvidence(id: String, skill: String, skillDir: URL) throws -> DraftEvidence {
        let evaluations = skillDir.appendingPathComponent("evaluations")
        // **Validate before the id ever touches a path (SECURITY).** `appendingPathComponent` treats `/`
        // as a separator and the OS resolves `..` at open time, so an unchecked id like `../../../secret`
        // reads a file outside the project — the safe reader refuses symlinks and special files but does
        // *not* confine a path. Reuse the project's own id rule (a date plus a lowercase-and-dashes name),
        // which structurally cannot contain `/`, `\`, or `.`. The message deliberately does not say
        // whether anything exists at that location, so a rejected id can't be used to probe the disk.
        guard EvidenceValidation.isValidID(id) else {
            throw EDDError.usage(
                message: "'\(id)' is not a valid evidence id",
                remedy: "ids look like 2026-06-09-slop-vocabulary — a date, then lowercase words joined by dashes")
        }
        // Build one component at a time (never a slash-bearing string), then confine the read below.
        let findings = evaluations.appendingPathComponent("findings").appendingPathComponent("\(id).md")
        let friction = evaluations.appendingPathComponent("friction").appendingPathComponent("\(id).md")
        let fm = FileManager.default
        // A plain file where an evidence folder belongs makes every lookup below return nothing, which
        // would surface as "no evidence named" — true in a useless way, and it hides the one fact that
        // lets the person fix it. Detection is shared with the clustering command; the reaction differs:
        // that one reports and continues, drafting must stop.
        if let broken = EvidenceLayout.misshapen(skillDir: skillDir).first {
            throw EDDError.invalidArtifact(
                path: broken.label,
                reason: "is a file, but a directory is expected here — remove or rename it")
        }
        // `fileExists` FOLLOWS links, so a link whose target is gone reads as absent and would be
        // reported as "no such evidence" (misuse) instead of the refusal a named-but-unreadable record
        // requires. Treat a link as present and let the confining reader classify it.
        // Two questions, not one. A *real file* in both folders is genuinely ambiguous; a shortcut is
        // only "present" so the safe reader can refuse it precisely instead of reporting "no such
        // evidence". Conflating them let a broken shortcut in one folder block the real record in the
        // other with an "ambiguous" error the reader never got to explain.
        let realInFindings = fm.fileExists(atPath: findings.path) && !SafeFile.isSymlink(findings)
        let realInFriction = fm.fileExists(atPath: friction.path) && !SafeFile.isSymlink(friction)
        let inFindings = realInFindings || SafeFile.isSymlink(findings)
        let inFriction = realInFriction || SafeFile.isSymlink(friction)

        if realInFindings && realInFriction {
            throw EDDError.usage(
                message: "evidence id '\(id)' exists in both findings/ and friction/ — ambiguous",
                remedy: "rename one of findings/\(id).md or friction/\(id).md")
        }
        guard inFindings || inFriction else {
            // Name what IS there, the way the unknown-skill error does. The set is small by design (the
            // taxonomy groups failures into a handful of categories), so the full list is the targeted
            // answer and needs no similarity threshold to mis-tune.
            let available = EvidenceLayout.availableIDs(skillDir: skillDir)
            throw EDDError.usage(
                message: "no evidence named '\(id)'",
                remedy: available.isEmpty
                    ? "no findings or friction notes recorded yet — run `skillet triage \(skill)` to mine some"
                    : "choose one of: \(available.joined(separator: ", "))")
        }
        // Prefer a real file over a shortcut, so a stray link never shadows the record you meant.
        let useFindings = realInFindings || (inFindings && !realInFriction)
        let url = useFindings ? findings : friction
        // The *folder* is plural ("findings"), the *kind* is singular ("finding") — errors must name the
        // real directory or they send the operator somewhere that does not exist.
        let folder = useFindings ? "findings" : "friction"
        // Second layer: confine the read to the evidence folder, so even a path that slipped the shape
        // check could not escape (defence in depth, the posture the rest of this codebase uses).
        let text: String
        switch SafeFile.readConfinedRegularText(url, base: evaluations, cap: evidenceCap) {
        case let .success(contents): text = contents
        case let .failure(refusal):
            throw EDDError.invalidArtifact(path: "\(folder)/\(id).md", reason: refusal.reason)
        }
        do {
            let (evidence, body) = try EvidenceFrontmatter.decode(text, filename: "\(id).md")
            // Shared rule (`Evidence.belongs(to:)`), fatal response: you named this record by hand, so
            // silently dropping it would answer a question you didn't ask. The bulk scan below applies
            // the same rule and merely skips — the fact is shared, the reaction is not.
            guard evidence.belongs(to: skill) else {
                throw EDDError.invalidArtifact(
                    path: "\(folder)/\(id).md",
                    reason: "belongs to skill '\(evidence.header.skill)', but you asked for '\(skill)' — it is filed in the wrong place")
            }
            return DraftEvidence(record: evidence, body: body)
        } catch {
            throw EDDError.invalidArtifact(path: "\(folder)/\(id).md", reason: "\(error)")
        }
    }

    /// All readable friction notes (for the shared-session join). A named record is fatal when it
    /// cannot be read (A17); a bulk-scan refusal is disclosed and skipped, so the join stays
    /// best-effort context while no failure is silent (A10).
    static func scanFriction(_ dir: URL, skill: String, disclosures: inout [Disclosure]) -> [DraftEvidence] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else {
            disclosures.append(Disclosure(subject: dir.lastPathComponent,
                                          reason: "is not a directory — friction scan skipped"))
            return []
        }
        let entries: [URL]
        do { entries = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) }
        catch {
            disclosures.append(Disclosure(subject: dir.lastPathComponent,
                                          reason: "could not list friction notes — \(error)"))
            return []
        }
        var out: [DraftEvidence] = []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard name.hasSuffix(".md"), !SafeFile.isHidden(name) else { continue }
            switch SafeFile.readPlainText(url, cap: evidenceCap) {
            case let .failure(refusal):
                disclosures.append(Disclosure(subject: "friction/\(name)", reason: refusal.reason))
                continue
            case let .success(text):
                do {
                    let (evidence, body) = try EvidenceFrontmatter.decode(text, filename: name)
                    // Same shared rule, disclosed response: nobody asked for this particular record —
                    // the session join swept it up — so a misfiled one is dropped with a note and the
                    // run continues. (Both rules were missing here entirely: the scanner trusted the
                    // folder for the label and never checked the skill at all.)
                    guard evidence.belongs(to: skill) else {
                        disclosures.append(Disclosure(
                            subject: "friction/\(name)",
                            reason: "belongs to skill '\(evidence.header.skill)' — not used as context for '\(skill)'"))
                        continue
                    }
                    out.append(DraftEvidence(record: evidence, body: body))
                } catch {
                    disclosures.append(Disclosure(subject: "friction/\(name)",
                                                  reason: "could not decode frontmatter — \(error)"))
                }
            }
        }
        return out
    }

    // MARK: - write

    static func validateOutName(_ name: String) throws {
        // Exactly the documented rule: no path separators, not the parent-directory form, and it must
        // end in `.json`. A leading dot was also being rejected, which is not in the contract — an
        // undocumented extra restriction is a surprise, and a hidden name in a scratch folder is harmless.
        guard !name.contains("/"), !name.contains("\\"), name != ".." else {
            throw EDDError.usage(message: "--out '\(name)' must be a bare filename inside .skillet/proposals/",
                                 remedy: "pass a name like fix-density.json")
        }
        guard name.hasSuffix(".json") else {
            throw EDDError.usage(message: "--out '\(name)' must end in .json",
                                 remedy: "pass a name like \(name).json")
        }
    }

    /// Prepare the cache the way `run` does, but targeting **this** command's directory, then write
    /// without overwriting. Returns the project-relative path, or `nil` when the write was refused.
    /// What happened to the write — the caller needs to know *which* no-write case occurred to say
    /// anything useful next, not merely that nothing was written.
    enum WriteOutcome {
        case written(path: String)
        /// Carries the draft that is **actually on disk**, so the summary can describe that file rather
        /// than the one just generated and thrown away.
        case identicalDraftExists(path: String, existing: ProposalSet)
        case nameTaken(path: String)
    }

    static func write(_ set: ProposalSet, named name: String, proposals: URL, projectRoot: URL,
                      disclosures: inout [Disclosure]) throws -> WriteOutcome {
        let dest = proposals.appendingPathComponent(name)
        let relative = ".skillet/proposals/\(name)"
        // Pre-check, so a collision is a clean disclosed refusal rather than a raw filesystem error
        // surfacing as an unexpected exit code (the triage finding-writer's pattern).
        if FileManager.default.fileExists(atPath: dest.path) || SafeFile.isSymlink(dest) {
            // Same name, but is it the same draft? The existing file records what produced it — which
            // evidence, which model, which instruction version — so compare rather than assume. This is
            // the idempotency-key rule: a key reused with the SAME inputs is a repeat, a key reused with
            // DIFFERENT inputs is its own error and must never be reported as a duplicate. Saying "you
            // already drafted this" about a different draft is exactly the misleading case.
            // Three outcomes, not two. Guessing between them is how "true but misleading" errors happen:
            // an unreadable file is NOT evidence of a different draft, it is its own problem.
            // Four outcomes, not three. A file refused for SIZE is not evidence of corruption, and
            // saying "could not be read" sent people looking for damage that was not there — the same
            // "true but misleading" shape as the three-way split above. Reading uses the draft budget,
            // which sits above what a reply may produce, so our own output always fits; only a file
            // swapped for something huge between runs can land here.
            enum Occupant { case sameDraft(ProposalSet), differentDraft, unreadable(String), tooLarge }
            var occupant: Occupant
            switch SafeFile.readPlainText(dest, cap: draftCap) {
            case let .failure(refusal):
                // Match the refusal's own case, not its wording — a reworded message must not silently
                // reclassify a size refusal as corruption.
                if case .oversized = refusal { occupant = .tooLarge }
                else { occupant = .unreadable(refusal.reason) }
            case let .success(text):
                if let existing = try? SkilletJSON.decode(ProposalSet.self, from: text) {
                    // One comparison, and an exact one: the stored fingerprint identifies the whole
                    // request. Comparing field-by-field was blind to everything not named in those
                    // fields — a record's body being edited, a newly related note, the skill file
                    // changing — each of which is a different request under the same name. Skill stays in
                    // the comparison because the output-name flag writes into one shared folder.
                    occupant = (existing.skill == set.skill
                                && existing.requestFingerprint == set.requestFingerprint)
                        ? .sameDraft(existing) : .differentDraft
                } else {
                    occupant = .unreadable("it is not a readable draft file")
                }
            }
            // **The one derived field that can go out of date.** `expected` is copied from the named
            // records' `eval` links — and those links are NOT part of the request, because the model is
            // never told which test covers a record. So the same request can legitimately imply a
            // different list than the file stores, and this is not an edge case: when nothing is linked
            // yet, this command's own closing advice is "write an eval so the fix can be proven". Do
            // exactly that, come back, and the saved file would still claim no test covers it.
            //
            // A stored copy of derived data needs a defined update path; this is the "update on write"
            // half of that pair. Only this field is re-derived, only when the fingerprint proves the
            // request is identical, and never silently — the refresh is disclosed like any other write.
            // Everything else, including anything you edited by hand, is carried over untouched.
            var refreshedExpected = false
            if case let .sameDraft(existing) = occupant, existing.expected != set.expected {
                let updated = ProposalSet(
                    id: existing.id, skill: existing.skill, motivation: existing.motivation,
                    expected: set.expected,
                    model: existing.model, promptVersion: existing.promptVersion,
                    requestFingerprint: existing.requestFingerprint, edits: existing.edits)
                do {
                    // Atomic: writes a neighbouring temp file and renames over the name, so a reader
                    // never sees a half-written draft. The path reached here is a real file we just read
                    // and decoded — a shortcut was refused above and never lands in this branch.
                    try Data((try SkilletJSON.encode(updated) + "\n").utf8).write(to: dest, options: .atomic)
                    occupant = .sameDraft(updated)
                    refreshedExpected = true
                } catch {
                    throw EDDError.cacheUnwritable(path: relative, reason: "\(error)")
                }
            }

            let reason: String
            switch occupant {
            case .sameDraft:
                reason = refreshedExpected
                    ? "this exact draft already exists — its list of evals was out of date and has been refreshed from the evidence; nothing else was changed"
                    : "this exact draft already exists (same skill, evidence, model and instructions) — nothing was rewritten"
            case .differentDraft:
                reason = "a different draft already occupies that name — nothing was overwritten; pass --out <name>.json to write this one"
            case let .unreadable(why):
                reason = "a file is already there and could not be read (\(why)) — nothing was overwritten; inspect or remove it, or pass --out <name>.json"
            case .tooLarge:
                reason = "a file is already there but is too large to check (over \(draftCap) bytes) — nothing was overwritten; inspect or remove it, or pass --out <name>.json"
            }
            disclosures.append(Disclosure(subject: relative, reason: reason))
            switch occupant {
            case let .sameDraft(existing): return .identicalDraftExists(path: relative, existing: existing)
            case .differentDraft, .unreadable, .tooLarge: return .nameTaken(path: relative)
            }
        }
        do {
            // Atomic **and** never-replacing: writing straight into the final name meant a crash
            // partway through left a truncated draft there, which the next run then reported as an
            // unreadable file occupying the name.
            try FileCreate.exclusively(try SkilletJSON.encode(set) + "\n", at: dest)
        } catch {
            // Same rule as the cache preparation: the machine refusing a write is an environment problem,
            // not the project's data being malformed. This line used to say "bad artifact", which
            // described a permissions failure as though the user's content were at fault.
            throw EDDError.cacheUnwritable(path: relative, reason: "\(error)")
        }
        return .written(path: relative)
    }
}
