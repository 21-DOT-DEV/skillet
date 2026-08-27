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
import IterateKit

/// `skillet iterate` — prove a reviewed edit by measuring the skill twice.
///
/// Measures the skill as it is, applies the chosen edits to a **disposable copy** of the repository,
/// measures it again, and reports the per-test difference with a verdict. Nothing you own is touched:
/// the copy is made outside your repository and removed afterwards, and landing a proven edit goes
/// through the command that writes your working tree.
///
/// **Both measurements are taken now**, in this one invocation. Reusing a stored earlier one would mean
/// the two halves differed by more than your edit — a different day, different sampling, possibly a
/// different model — and the number would be read as "my edit did this".
struct IterateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iterate",
        abstract: "Prove a reviewed SKILL.md edit by measuring the skill before and after it.",
        discussion: """
        Reads a draft you have already reviewed, applies the edits you choose into a throwaway copy of \
        this repository, and measures the same tests against both versions in one go. It prints each \
        test's before and after, an average difference with an honest error bar, and a verdict.

        THE VERDICT IS STRICT: any test scoring lower blocks, even when the drop is small enough to be \
        run-to-run variation — those are marked so you can judge, never silently discounted. It is also \
        PROVISIONAL, because how often the automatic grader agrees with a person has not been measured.

        NOTHING IS COMMITTED AND YOUR FILES ARE NOT CHANGED. A proven edit is landed with \
        `skillet suggest <skill> --proposals <name>.json --apply`, which writes your working tree.

        This is the most expensive command here — two measurements, so roughly double a single run.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "The skill to prove an edit against.")
    var skill: String

    @Option(name: .long, help: "Filename of a saved draft inside .skillet/proposals/.")
    var proposals: String

    @Option(name: .long, parsing: .upToNextOption,
            help: "Prove only these edits, numbered from 0 in draft order (default: all of them).")
    var edits: [Int] = []

    @Option(name: .long, help: "Trials per eval; overrides runs.k from skillet.yaml.")
    var runs: Int?

    @Flag(name: [.customShort("n"), .long],
          help: "Show what would be measured and what it would cost, then stop without spending.")
    var dryRun = false

    @Flag(name: .long, help: "Proceed past the cost confirmation without prompting.")
    var yes = false

    @Flag(name: .long, help: "Never prompt; a confirmation that would have been asked is refused instead.")
    var noInput = false

    @Option(name: .customLong("judge"),
            help: "Grader for the two measurements: text-judge (default) or grounded-judge (reads produced-file contents to catch created-but-wrong).")
    var judgeSelection: String = TextJudge.id

    @Flag(name: .customLong("keep-worktree"),
          help: "Keep the disposable copy instead of removing it, for inspecting what happened.")
    var keepWorktree = false

    @Flag(name: .long, help: ArgumentHelp("Test-only: measure offline with canned answers.",
                                          visibility: .private))
    var replay = false

    @Option(name: .customLong("replay-map"),
            help: ArgumentHelp("Test-only: canned verdicts for the offline measurement.",
                               visibility: .private))
    var replayMap: String?

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            try await prove(renderer: renderer)
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        } catch let error as SilentExit {
            throw error
        } catch {
            let classified = EDDError.internalError(detail: "\(error)")
            Console.emit(renderer.renderError(classified))
            throw SilentExit(code: classified.exitCode.rawValue)
        }
    }
}

extension IterateCommand {
    /// What the measuring scope hands back once the copy has been removed. `nil` in place of one of
    /// these means nothing was measured (`--dry-run`).
    struct Measured {
        let before: Runner.Outcome
        let after: Runner.Outcome
        /// Set only when the copy was deliberately left behind, so the report can name it.
        let keptCopy: String?
    }

    /// The order matters: everything free answers before anything paid, and a mistake in what you typed
    /// answers before anything about the state of your machine.
    func prove(renderer: Renderer) async throws {
        // **Each hidden switch is checked on its own, matching the measuring command.** Checking them
        // together and naming whichever came first still refuses today, because one gate covers both —
        // but it names only one of the switches actually used, and it silently becomes a hole the moment
        // the two switches are gated differently. Written the same way in both commands so neither can
        // drift into being the lenient one.
        if replay { try TestSeam.assertEnabled("--replay") }
        if replayMap != nil { try TestSeam.assertEnabled("--replay-map") }
        try TestSeam.assertRecordingsUsable(replay: replay, provided: [replayMap.map { _ in "--replay-map" }])
        try SuggestCommand.validateOutName(proposals, flag: "--proposals")

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
        guard let root = context.root.map({ URL(fileURLWithPath: $0) }) else {
            throw EDDError.projectNotFound(cwd: context.cwd)
        }
        let config = try loadConfig(options: options, context: context)
        // Same routine, same defaults, same refusals as the measuring command — and the value it hands
        // back is what the model-wiring step below demands, so nothing here can run on a number that was
        // never checked. Two of the three literals this replaces had drifted from the declared defaults.
        let approved = try SpendGate.approveSettings(config?.runs ?? .init(), runsFlag: runs)
        let skillsRoot = config?.project?.skillsRoot ?? "skills"
        let discovered = SkillScanner().scan(skillsRoot: root.appendingPathComponent(skillsRoot))
        guard let skillDir = try selectSkillDirectories(discovered, requested: [skill], command: "iterate").first else {
            throw EDDError.usage(message: "no skill named '\(skill)'",
                                 remedy: "run `skillet lint` to list what is discovered")
        }
        try TriageCommand.assertConfined(skillDir: skillDir, projectRoot: root, skill: skill)

        // ---- the draft, and which of its edits ------------------------------------------------------
        let relativeDraft = projectRelativePath(".skillet/proposals", proposals)
        let draftURL = root.appendingPathComponent(".skillet/proposals").appendingPathComponent(proposals)
        let text: String
        switch SafeFile.readConfinedRegularText(draftURL, base: root, cap: SuggestCommand.fileReadCap) {
        case let .success(contents): text = contents
        case let .failure(refusal): throw refusal.rejection(path: relativeDraft)
        }
        let set: ProposalSet
        do { set = try SkilletJSON.decode(ProposalSet.self, from: text) }
        catch {
            throw EDDError.invalidArtifact(path: relativeDraft,
                                           reason: "not a readable draft — \(DecodeFailure.describe(error))")
        }
        guard set.skill == skill else {
            throw EDDError.usage(message: "\(relativeDraft) is a draft for '\(set.skill)', not '\(skill)'",
                                 remedy: "name the skill the draft was written for")
        }
        guard !set.edits.isEmpty else {
            throw EDDError.usage(message: "\(relativeDraft) contains no edits",
                                 remedy: "draft again — there is nothing here to prove")
        }
        // Range, repeats, and canonical order — the same routine the command that writes your files
        // calls. Repeats used to reach the overlap test here and be reported as edit 0 overlapping
        // itself, at the number reserved for a deliberate safety refusal (see `EditSelection`).
        let chosen = try EditSelection.resolve(edits, in: relativeDraft, count: set.edits.count,
                                               verb: .prove)

        // **The same two graders the measuring command offers, checked the same way and before spending.**
        // Hard-wiring the text grader meant an edit repairing *wrong file contents* could not be proven:
        // this command's whole job is to re-measure, and it could not measure what the sibling command
        // can. Validated here, ahead of anything about the state of the project, because a mistyped
        // grader is a mistake in what you typed.
        guard judgeSelection == TextJudge.id || judgeSelection == GroundedJudge.id else {
            throw EDDError.usage(message: "unknown judge '\(judgeSelection)'",
                                 remedy: "use --judge \(TextJudge.id) (default) or --judge \(GroundedJudge.id)")
        }
        if judgeSelection == GroundedJudge.id {
            // Said before you approve the cost, not after: this command already spends twice, and the
            // file-reading grader makes each grading request larger again.
            Console.emit(Rendering(stderr: "note: grounded judge includes file contents — larger grading "
                + "requests, higher per-call cost (up to ~128 KiB of file text each), and this command "
                + "grades twice\n"))
        }

        // ---- a clean repository, because the copy is built from what is committed --------------------
        if let dirt = try await SuggestCommand.repositoryDirt(root: root) {
            throw EDDError.gate(
                message: "\(dirt.reason), so nothing was measured",
                remedy: "commit or stash everything first — the copy this measures is built from your last "
                    + "commit, so uncommitted work would make the two measurements differ by more than the edit")
        }

        // ---- the copy, the edit, and every free refusal — all before the cost question ---------------
        // The copy costs nothing to make, so it is made first: the edited version is what the free static
        // checks must read (gating on the state *before* a change would refuse to prove the very repair
        // you wrote), and that puts every free check ahead of anything paid, which is this project's rule.
        let evalCases = try Self.behaviourEvals(skillDir: skillDir, skillName: skill)
        let k = approved.k
        let trials = evalCases.count * k * 2                   // two measurements
        let estimatedCalls = trials * 2                        // an answer and a grading per trial

        // **The copy's lifetime belongs to this scope**, so it is removed on every way out — a refused
        // edit, a failed measurement, an interrupted one — not only on the path that happens to succeed.
        let (measured, survived) = try await ThrowawayCopy.withCopy(of: root, for: skill,
                                                        keep: keepWorktree) { copy -> Measured? in
            // **Built from what we already know, not by cutting the project path out of the skill path.**
            // Text surgery breaks whenever one path is written differently from the other — here the
            // project sat at `/tmp/x` while the skill resolved through `/private/tmp/x`, so removing
            // `/tmp/x/` ate a piece of the middle and produced `/privateskills/demo`. The same
            // partial-path trap this project already documents in its confinement checks.
            let relativeSkill = projectRelativePath(skillsRoot, skillDir.lastPathComponent)
            let copySkillDir = copy.appendingPathComponent(relativeSkill)
            let copySkillFile = copySkillDir.appendingPathComponent("SKILL.md")
            let original: String
            switch SafeFile.readConfinedRegularText(copySkillFile, base: copy, cap: SuggestCommand.fileReadCap) {
            case let .success(contents): original = contents
            case let .failure(refusal): throw refusal.rejection(path: "\(relativeSkill)/SKILL.md")
            }
            // **The canonical list, not the raw flag.** Measuring one subset while planning another is
            // how `--edits 0 0` got past the checks above and into the applying engine.
            switch EditApply.plan(set.edits,
                                  selecting: EditSelection.planSelection(chosen, count: set.edits.count),
                                  in: original,
                                  editableFileName: ProposalDrafter.editableFileName) {
            case let .ready(placements):
                try FileCreate.replacingContents(of: copySkillFile,
                                                 with: EditApply.apply(placements, to: original))
            case let .refused(reasons):
                throw SuggestCommand.refusalError(reasons, draft: relativeDraft, editCount: set.edits.count)
            }

            // The same four free refusals the measuring command applies, from the same routine — fixtures,
            // something to grade, no shortcuts inside the bundle, and the static catalog. The first three
            // read your skill (the copy is your last commit, so they agree); the static one reads the
            // **edited** copy, so a repair is never blocked and a breaking edit is still refused for free.
            try SpendGate.assertFreeChecksPass(
                cases: evalCases, skillDir: skillDir, skillName: skill,
                lintTarget: copySkillDir, lintConfig: config?.lint ?? .init(), renderer: renderer)

            // ---- what it costs, and whether you agree ------------------------------------------------
            // The shared threshold, not a lower one: it counts trials, and the doubling above already
            // put this command at half the repetitions. `run --ab` doubles too and keeps the same number.
            let limit = approved.confirmAboveTrials
            if dryRun {
                // **A machine-readable preview when one is asked for.** Every command here offers one and
                // every one carries a schema; this branch used to hand back prose regardless, so a script
                // asking for a plan got a table meant for a person. Same shape as the measuring
                // command's (`RunPlan`), for the command that measures twice.
                if options.json {
                    let plan = IteratePlan(
                        skill: skill, proposals: proposals, edits: chosen, evals: evalCases.count, k: k,
                        trials: trials, confirmAboveTrials: limit,
                        requiresConfirmation: trials > limit, willSpend: !replay,
                        estimatedCalls: estimatedCalls)
                    Console.emit(Rendering(stdout: try SkilletJSON.encode(plan) + "\n"))
                    return nil
                }
                var lines = ["iterate — \(skill) (dry run: nothing measured, nothing spent)",
                             "  draft            \(relativeDraft)",
                             "  edits            \(chosen.map(String.init).joined(separator: ", "))",
                             "  plan             \(evalCases.count) \(evalCases.count == 1 ? "eval" : "evals")"
                                 + " × k=\(k) × 2 measurements = "
                                 + "\(trials) \(trials == 1 ? "trial" : "trials") ≈ "
                                 + "\(estimatedCalls) model \(estimatedCalls == 1 ? "call" : "calls")"]
                // **A preview that leaves something behind says so.** The copy is made before this point
                // (the free static checks read the edited version), so asking to keep it keeps it here
                // too — and saying nothing left a folder on disk and an entry in git's own list of copies
                // that nothing had told you about.
                if keepWorktree { lines.append("  copy kept        \(copy.path)") }
                lines.append("→ next: re-run without --dry-run to measure")
                Console.emit(Rendering(stdout: lines.joined(separator: "\n") + "\n\n"))
                return nil
            }
            switch SpendGate.confirmCost(trials: trials, estimatedCalls: estimatedCalls, limit: limit,
                                         skill: skill, yes: yes, noInput: noInput) {
            case .proceed: break
            case let .declined(estimate), let .notAsked(estimate):
                // A deliberate check said no and nothing was done — which is what `5` means here, unlike
                // the measuring command, whose `2` predates the table (see Specs/020 D8).
                throw EDDError.gate(message: "cost not confirmed: \(estimate)",
                                    remedy: "re-run with --yes to proceed, or --dry-run to preview")
            }

            let judgeCfg = config?.judge ?? .init()
            let wiring = try MeasurementSetup.forBehaviour(
                config: config, judge: judgeCfg, approved: approved, judgeSelection: judgeSelection,
                offline: replay ? .init(verdicts: try RunCommand.decodeVerdictMap(replayMap, projectRoot: root),
                                      defaultPass: replayMap == nil) : nil)
            try await SpendGate.assertHarnessReady(wiring.adapter, strict: !replay)

            // Each measurement writes into its own folder under this project — never into the copy, which
            // is about to be removed, and never into the other's, which would overwrite it file for file.
            // Prepared through the shared routine, which refuses a `.skillet`/`.skillet/runs` that is a
            // shortcut to somewhere else; writing straight to the path sent six raw transcripts outside
            // the project and still reported success, while the measuring command refused the same setup.
            // **The whole identifier, not the first eight characters of it.** Eight hex characters is a
            // birthday bound on thirty-two bits, and the second-resolution timestamp beside it narrows the
            // window without removing it — several runs starting in the same second is ordinary on a build
            // machine. What makes it worth removing is how a clash fails: asking for a folder that already
            // exists succeeds silently, so the second run would write its transcripts, traces and records
            // into the first run's folder, and preparing a workspace there deletes what is already in it.
            // Measured: creating an existing folder returns success and leaves the earlier file in place.
            //
            // The throwaway-copy path already uses the whole identifier for the same reason, and it is the
            // *safer* of the two — a clash there is refused outright rather than silently accepted.
            let stamp = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
            let runsBase = try CacheSupport.prepareCacheDirectory(projectRoot: root, subdirectory: "runs")
                .appendingPathComponent("iterate-\(stamp)", isDirectory: true)
            let runner = Runner(adapter: wiring.adapter, judge: wiring.judge, evidencePolicy: wiring.policy)
            let beforeOutcome = try await runner.run(
                skill: SkillRef(name: skill, path: skillDir.path), evals: evalCases, k: k,
                injection: .only(load: [SkillRef(name: skill, path: skillDir.path)]),
                base: runsBase.appendingPathComponent("before", isDirectory: true))
            let afterOutcome = try await runner.run(
                skill: SkillRef(name: skill, path: copySkillDir.path),
                evals: evalCases, k: k,
                injection: .only(load: [SkillRef(name: skill, path: copySkillDir.path)]),
                base: runsBase.appendingPathComponent("after", isDirectory: true))
            return Measured(before: beforeOutcome, after: afterOutcome,
                            keptCopy: keepWorktree ? copy.path : nil)
        }
        // A copy that outlived the run when it should not have is disclosed, not left unmentioned.
        let disclosures = survived.map {
            [Disclosure(subject: "throwaway copy",
                        reason: "could not be removed and is still at \($0.path) — clear it with "
                            + "`git worktree remove --force \($0.path)`")]
        } ?? []
        guard let measured else {                  // --dry-run: nothing measured
            for disclosure in disclosures {
                Console.emit(Rendering(stdout: "  ! \(disclosure.subject): \(disclosure.reason)\n"))
            }
            return
        }

        // ---- the verdict ------------------------------------------------------------------------------
        // **The names are proved unique here, once, before anything is compared.** The tests file was
        // already refused if it repeated a name, so this cannot fail in practice — but the comparison
        // takes a set that cannot hold a repeat, rather than a list plus a hope.
        let verdict = EditVerdict.compare(before: try Self.measurements(measured.before),
                                          after: try Self.measurements(measured.after))
        let perEval: [IterateReport.Comparison.Row] = verdict.rows.map { row in
            IterateReport.Comparison.Row(
                id: row.id,
                beforePasses: row.before?.passes ?? 0, beforeRecorded: row.before?.recorded ?? 0,
                afterPasses: row.after?.passes ?? 0, afterRecorded: row.after?.recorded ?? 0,
                delta: row.delta, noisy: row.noisy)
        }
        // **A test nothing ran is named, not silently dropped from the average.** It stays in the table
        // above but is out of the average, and an omission the reader cannot see is what this list exists
        // to prevent. Empty on every ordinary run: a test with no instruction to send is refused before
        // anything is spent, and both measurements run the same list.
        let reported = disclosures
            + [verdict.unmeasuredDisclosure, verdict.noPassingEvidenceDisclosure].compactMap { $0 }
        let comparison = IterateReport.Comparison(
            perEval: perEval, meanDelta: verdict.meanDelta, standardError: verdict.standardError,
            improved: verdict.improvements.count, regressed: verdict.regressions.count)
        // **It offers exactly what was measured.** Proving a subset and then printing the command that
        // applies the whole draft recommends shipping edits nothing measured — the same fault as a
        // verdict drawn from zero trials, arriving by a different route. The flag is added only when the
        // subset is genuinely narrower, so the everything case stays the short command it always was.
        // **The subset flag joins the others rather than being stuck on the end.** When the skill's name
        // starts with a hyphen the command has to end with the end-of-options marker and the name, and
        // anything appended after that is read as another name rather than as a switch — so a flag added
        // here after the line was built would be silently dropped from the command it belongs to.
        var landOptions = [ShellWord.option("--proposals", proposals), "--apply"]
        if chosen != Array(set.edits.indices) {
            landOptions.append("--edits " + chosen.map(String.init).joined(separator: " "))
        }
        let landCommand = ShellWord.command("skillet suggest", skill, options: landOptions)
        // The repeats are derived from what was recorded, inside the report — it cannot be told a
        // different number. See `IterateReport.init`. The kept copy and the command that lands the edit
        // travel in the report too, so a script is told what a person is shown rather than having to
        // rebuild the command from its parts and get a flag subtly wrong.
        let report = IterateReport(
            skill: skill, proposals: proposals, edits: chosen, proven: verdict.proven,
            comparison: comparison, disclosures: reported,
            keptCopy: measured.keptCopy, landCommand: landCommand)
        Console.emit(try renderer.renderIterate(report, keptCopy: measured.keptCopy,
                                                landCommand: landCommand))
        if !verdict.proven { throw SilentExit(code: ExitCode.measuredFailure.rawValue) }
    }

    /// The behaviour tests for this skill. Refuses when there are none, because a proof with nothing to
    /// measure is not a proof.
    static func behaviourEvals(skillDir: URL, skillName: String) throws -> [EvalCase] {
        let raw = try SkillReader().read(skillDirectory: skillDir)
        guard let data = raw.evalsJSON else {
            throw EDDError.usage(message: "no evals to measure for \(skillName)",
                                 remedy: "add evaluations/evals.json — an edit cannot be proven without tests")
        }
        let file: EvalsFile
        do { file = try JSONDecoder().decode(EvalsFile.self, from: data) }
        catch {
            throw EDDError.invalidArtifact(path: "\(skillName)/evaluations/evals.json",
                                           reason: "not valid evals.json — \(DecodeFailure.describe(error))")
        }
        guard !file.cases.isEmpty else {
            throw EDDError.usage(message: "\(skillName) has no evals to measure",
                                 remedy: "add at least one case to evaluations/evals.json")
        }
        return file.cases
    }

    /// Per-test counts, which is all the verdict needs.
    static func measurements(_ outcome: Runner.Outcome) throws -> UniqueByName<EditVerdict.Measurement> {
        try UniqueByName(
            outcome.evals.map { result in
                // The rule lives with the type, where a test can reach it — see `Measurement.init(_:)`.
                EditVerdict.Measurement(result)
            },
            name: \.id)
    }
}
