import Foundation
import EDDCore
import HarnessKit
import RenderKit
import RunKit
import ConfigYAML
import ProjectKit

/// The one check every paid command must pass **before** it spends.
///
/// It refuses a model program that is a known-bad version, or one you are not signed in to — so the
/// failure arrives as a clear, free refusal instead of a confusing error part-way through a paid call.
///
/// **Why this is a single routine rather than a line in each command.** It previously lived only inside
/// the measured-run command; when the drafting command was added it simply forgot, so that command could
/// spend against a blocked or signed-out setup and the corresponding refusals were unreachable from it.
/// That is the textbook argument for one enforcement point: several implementations, most correct and one
/// flawed, is precisely the failure mode a single shared routine prevents — and every path to the same
/// operation must apply the same checks. A future paid command inherits this by calling one function.
enum SpendGate {
    /// **The run settings, checked once and proved by their own existence.**
    ///
    /// A value of this type can only be produced by `approveSettings` below, and the step that picks the
    /// model and the grader will not accept anything else. So a command cannot reach a paid measurement
    /// carrying numbers nothing checked — forgetting is a compile error rather than something a reviewer
    /// has to spot. (The pattern is a *witness*: constructing the value is the proof that the check ran.)
    ///
    /// **Why it exists.** The same defect appeared five times in one feature — a guard present in the
    /// measuring command and simply absent from the proving one. Sharing the guard fixes today's five;
    /// only requiring its result fixes the sixth, in a command nobody has written yet.
    struct Approved {
        /// Repetitions per test. At least 1 — measuring nothing must never read as "nothing got worse".
        let k: Int
        /// Cap on how much output a single attempt may produce. Positive.
        let outputLimitBytes: Int
        /// Time limit for a single attempt.
        let timeout: Duration
        /// Trial count above which the cost is put to you before anything is spent.
        let confirmAboveTrials: Int

        /// Private on purpose: `approveSettings` is the only way to get one.
        fileprivate init(k: Int, outputLimitBytes: Int, timeout: Duration, confirmAboveTrials: Int) {
            self.k = k
            self.outputLimitBytes = outputLimitBytes
            self.timeout = timeout
            self.confirmAboveTrials = confirmAboveTrials
        }
    }

    /// Resolve and check every number a measurement runs on, in one place for every paid command.
    ///
    /// **Defaults come from the settings type, never from a literal at the point of use.** Both numbers
    /// that were re-typed by hand in the proving command had drifted: it capped a single attempt's output
    /// at 4 MiB where the declared default is 64 MiB (small enough to cut off a long session and record
    /// the trial as a failure that has nothing to do with the skill), and it put the cost to you above 20
    /// trials where the declared default is 25.
    ///
    /// **The threshold is not lowered for a costlier command, deliberately.** It counts *trials*, and a
    /// command taking two measurements already counts double — so it already asks at half the repetitions.
    /// The one other command here that doubles its work (`run --ab`, which adds a skill-free comparison
    /// arm) keeps the same threshold for exactly that reason. A lower number would count the same cost
    /// twice.
    ///
    /// **A refusal names where the value came from** — the flag you typed or the file you wrote — because
    /// the message this replaces advised *"pass --runs with a value ≥ 1, or omit it to use runs.k"* even
    /// when `runs.k` was itself the cause, sending you to the setting that had just been refused.
    static func approveSettings(_ runs: SkilletConfig.Runs, runsFlag: Int?) throws -> Approved {
        let k = runsFlag ?? runs.k
        guard k >= 1 else {
            throw runsFlag != nil
                ? EDDError.usage(message: "--runs must be at least 1 (got \(k))",
                                 remedy: "pass --runs with a value ≥ 1, or omit it to use runs.k from skillet.yaml")
                : EDDError.usage(message: "runs.k must be at least 1 (got \(k))",
                                 remedy: "set a positive number of repetitions under `runs:` in skillet.yaml, "
                                     + "or omit it for the default of 3")
        }
        guard runs.maxOutputBytes > 0 else {
            throw EDDError.usage(
                message: "runs.max_output_bytes must be positive (got \(runs.maxOutputBytes))",
                remedy: "set a positive byte count in skillet.yaml, or omit it for the 64 MiB default")
        }
        // **Below zero, the cost question can never be answered.** The check is `trials > limit`, so a
        // negative limit is true for every run: each invocation stops to ask, and with prompting off —
        // a scheduled job, a pipe, `--no-input` — it cannot ask, so it refuses outright. The free
        // preflight meanwhile printed a tick beside it. Zero is allowed and meaningful: it means ask
        // about everything.
        guard runs.confirmAboveTrials >= 0 else {
            throw EDDError.usage(
                message: "runs.confirm_above_trials must not be negative (got \(runs.confirmAboveTrials))",
                remedy: "set a trial count in skillet.yaml above which the cost is put to you — 0 asks "
                    + "about every run — or omit it for the default of 25")
        }
        // **A time limit nobody can read is refused, not quietly replaced.** It used to fall back to ten
        // minutes in silence, so `timeout: "10 minutes"` — or any other near-miss — capped every attempt
        // at ten minutes while the file said otherwise, and an attempt stopped on time is recorded as a
        // failed one. A setting that silently fails to apply is already broken; refusing reports that.
        guard let timeout = DurationString.parse(runs.timeout) else {
            throw EDDError.usage(
                message: "runs.timeout is not a duration this understands: \"\(runs.timeout)\"",
                remedy: "write a number with a unit — 500ms, 30s, 10m, 2h — or a bare number meaning seconds")
        }
        return Approved(k: k, outputLimitBytes: runs.maxOutputBytes, timeout: timeout,
                        confirmAboveTrials: runs.confirmAboveTrials)
    }

    /// Probe the harness and refuse if it is unusable. Returns the harness details, because a caller may
    /// also need them (the measured-run command stamps the version into its records).
    ///
    /// `strict` is what turns an auto-discovered bad version from a warning into a refusal; paid paths
    /// pass `true`. The measured-run command relaxes it only for its canned offline mode, which spends
    /// nothing.
    @discardableResult
    static func assertHarnessReady(_ adapter: any HarnessAdapter, strict: Bool = true) async throws -> HarnessInfo {
        try await adapter.probe(strict: strict)
    }

    /// What asking about the cost came to. **This routine raises nothing**, deliberately: the two paid
    /// commands leave different numbers behind when you decline, so turning a refusal into an error is
    /// the caller's job and only the *asking* is shared. Moving the error in here as well would have
    /// silently changed what the measured run leaves behind.
    enum CostAnswer: Equatable {
        /// Under the threshold, or `--yes` was passed — nothing was asked and nothing blocks.
        case proceed
        /// A prompt was shown and the answer was not yes.
        case declined(estimate: String)
        /// No prompt was possible — not a terminal, or prompting was switched off — so it was not asked.
        case notAsked(estimate: String)
    }

    /// Ask about the cost, if the cost is worth asking about.
    ///
    /// Extracted from the measured-run command, which held it privately, so a second paid command cannot
    /// quietly ship without it — the same argument that put the readiness check above in one place, after
    /// a paid command was added that forgot it.
    ///
    /// **Waiting for a typed answer stops this thread, and that is safe here for a reason worth stating.**
    /// Reading a line blocks; both commands that call it are doing asynchronous work, and blocking a
    /// thread that asynchronous work shares can, in general, leave other work with nowhere to run.
    /// Nothing else is running at this moment: neither command starts any concurrent work at all — no
    /// task group, no parallel trials, nothing detached — and this question is asked before the first
    /// subprocess is launched, so there is nothing to starve. Reviewed 2026-08-21 and deliberately left
    /// alone, because isolating the wait would add machinery for a problem that cannot occur.
    ///
    /// **What would make it unsafe:** running trials concurrently, or asking anything else once
    /// measurement is under way. If either arrives, this must move off the shared threads first.
    static func confirmCost(trials: Int, estimatedCalls: Int, limit: Int, skill: String,
                            yes: Bool, noInput: Bool) -> CostAnswer {
        guard trials > limit, !yes else { return .proceed }
        let estimate = "\(trials) trials (≈ \(estimatedCalls) model calls) for \(skill) exceeds confirm_above_trials=\(limit)"
        // The question goes to the error stream and the answer comes from the input stream, so those are
        // the two that decide whether asking is possible. Checking the results stream — which carries
        // neither — turned the ordinary habit of saving results to a file into a refused run.
        guard Console.isStderrTTY(), Console.isStdinTTY(), !noInput else { return .notAsked(estimate: estimate) }
        FileHandle.standardError.write(Data("\(estimate). Proceed? [y/N] ".utf8))
        let answer = (readLine() ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return (answer == "y" || answer == "yes") ? .proceed : .declined(estimate: estimate)
    }

    /// **Everything free, before anything paid.** Four refusals that cost nothing to reach and would
    /// otherwise arrive only after money had been approved: a test naming a file that is missing or out
    /// of bounds, a test with nothing to grade, a skill folder containing a shortcut to somewhere else,
    /// and the free static checks.
    ///
    /// **Why here rather than in each command.** All four lived privately inside the measured-run
    /// command, so the proving command — which spends twice as much — reached none of them: a missing
    /// fixture was silently skipped and could surface as a "regression" the edit did not cause. That is
    /// the third time in this feature a check existed in one command and was simply absent from the
    /// other. One routine, called by both, is what stops the fourth command inheriting the same gap.
    ///
    /// `cases` is `nil` when no behaviour tests are being run; that also relaxes the static rule that
    /// requires an `evals.json`, so the two can never disagree about whether behaviour tests are running.
    ///
    /// **`lintTarget` is the version the static checks read**, which is not always the skill on disk. The
    /// measured run passes your skill. The proving command passes the *edited copy*, because gating on
    /// the state before a change would refuse to prove the very repair you wrote — while still refusing
    /// to spend on an edit that leaves the file broken in some other way (Specs/020 D10).
    static func assertFreeChecksPass(cases: [EvalCase]?, skillDir: URL, skillName: String,
                                     lintTarget: URL, lintConfig: SkilletConfig.Lint,
                                     renderer: Renderer) throws {
        // **The record already on disk has to still be scorable, and this is checked before anything is
        // spent.** A run keeps whichever half of the results file it did not measure this time, copying it
        // forward unchanged — that is how measuring one thing cannot destroy the record of the other. But
        // the part being copied was never checked, while the reader that scores the file refuses a count
        // that is not a whole number or a test named twice. So a file with either fault was carried
        // straight through, the run finished successfully, and what it left behind could not be scored by
        // this tool's own reader. Reproduced: a routing entry saying `2.5` runs came back out unchanged
        // after a clean run.
        //
        // **Refused here rather than at the moment of writing**, because writing happens after the
        // measurement — by then the money is spent and refusing would throw the results away. And refused
        // rather than quietly dropped, because dropping loses the committed record of the half that did
        // not run this time, which is the very thing carrying it forward exists to protect. The message
        // comes from the reader itself and already says which entry and what to do about it.
        let committed = skillDir.appendingPathComponent("evaluations/benchmark.json")
        if case let .success(data) = SafeFile.readPlainData(committed, cap: 8 << 20) {
            if let file = try? JSONDecoder().decode(BenchmarkFile.self, from: data) {
                _ = try RunReport(benchmark: file)
            } else if !data.isEmpty {
                // **A file that is not a results file at all is replaced, and that is said out loud.**
                // Two situations that look alike are handled differently on purpose. A file that reads as
                // a results file but holds something unscorable — a count that is not a whole number, a
                // test named twice — is refused above, because it carries real history the person can
                // repair, and replacing it would throw that away. A file that does not read as one at all
                // carries no history to lose, and is replaced by the ordinary write at the end of the run:
                // that is deliberate, because refusing instead would let anyone stop every future run by
                // dropping a broken file into place, and because a planted one previously hung the writer
                // after the money was spent.
                //
                // What was missing was the telling. Replacing it silently means the record of whichever
                // half of the results did not run this time disappears with no word — so it is announced
                // before anything is spent, while there is still time to take a copy.
                Console.emit(Rendering(stderr: "note: evaluations/benchmark.json is not a readable results "
                    + "file and will be replaced by this run — any earlier results in it, including for an "
                    + "axis this run does not measure, will be lost. Copy it first if you need it.\n"))
            }
        }
        if let cases {
            // Fixtures: present + resolvable under the fixture allowlist (`resolveFixture` rejects
            // absolute / `..` / symlink / hidden, and any evaluations/** that isn't
            // evaluations/fixtures/**).
            for eval in cases {
                for file in eval.files {
                    guard let fixture = WorkspaceManager.resolveFixture(file, skillDir: skillDir),
                          FileManager.default.fileExists(atPath: fixture.source.path) else {
                        throw EDDError.invalidArtifact(
                            path: "\(skillName)/evaluations/evals.json",
                            reason: "eval references a fixture that is missing, out-of-skill, symlinked, hidden, or private (only fixtures/** and evaluations/fixtures/** are allowed): \(file)",
                            fix: "point the eval at a real, readable file under the skill's own fixtures/ or evaluations/fixtures/ folder"
                        )
                    }
                }
            }
            // **A test with no instruction to send cannot run, and that is not the same as failing.**
            // Left through, it recorded nothing: the measuring command counted it as a failed test, while
            // the proving command compared nothing against nothing, called it no change, declared the
            // edit proven and offered the command that lands it. Refusing here costs nothing and stops
            // both. The wider convention agrees — a test runner that cannot load a test reports that
            // separately from a test that ran and failed, and the closest tool of this kind validates
            // its test files before spending anything.
            for (index, eval) in cases.enumerated()
            where (eval.prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw EDDError.invalidArtifact(
                    path: "\(skillName)/evaluations/evals.json",
                    reason: "eval '\(eval.id ?? "#\(index)")' has no prompt to send",
                    fix: "give the eval a `prompt` — the instruction the model receives — or remove it")
            }
            // An eval with no expectations can't measure behavior — reject it rather than letting a
            // verdict-less trial pass vacuously.
            for (index, eval) in cases.enumerated() where eval.expectations.isEmpty {
                throw EDDError.invalidArtifact(
                    path: "\(skillName)/evaluations/evals.json",
                    reason: "eval '\(eval.id ?? "#\(index)")' has no expectations to grade"
                )
            }
            // **No two tests may answer to the same name.** That name is the key every comparison joins
            // on — before against after, with-skill against without, this week's results against last
            // week's — so two tests sharing one leaves a comparison unable to say which it means, and
            // one test's result silently absent from it. Measured before this check existed: two tests
            // both named `same`, the first improving and the second getting worse, produced a single row
            // reading `+1.00`, the verdict "no test scored lower", and an offer to apply the edit.
            //
            // Compared on the name each test **actually gets**, not only the one written down, since a
            // test may leave its name out and be named from its own content instead.
            var seenNames: Set<String> = []
            for (index, eval) in cases.enumerated() {
                let name = EvalName.resolve(id: eval.id, prompt: eval.prompt, position: index)
                guard seenNames.insert(name).inserted else {
                    throw EDDError.invalidArtifact(
                        path: "\(skillName)/evaluations/evals.json",
                        reason: "two evals are both named '\(name)'",
                        fix: eval.id == nil
                            ? "give these evals different prompts, or an explicit `id` each — a name has "
                                + "to identify one eval, because results are matched up by it"
                            : "rename one of them — a name has to identify one eval, because results are "
                                + "matched up by it")
                }
            }
            // Skill bundle: no symlink anywhere in a staged entry (F7 treats symlinks as invalid
            // artifacts).
            for entry in WorkspaceManager.stagedEntries(skillDir: skillDir) {
                if let link = WorkspaceManager.firstSymlink(in: skillDir.appendingPathComponent(entry)) {
                    throw EDDError.invalidArtifact(
                        path: "\(skillName)",
                        reason: "skill bundle contains a symlink (not allowed in Phase 1): \(entry)/…/\(link.lastPathComponent)",
                        fix: "replace that link inside the skill folder with the real file, so what is measured is what is committed"
                    )
                }
            }
        }
        try runFreeLintGate(skillDir: lintTarget, lintConfig: lintConfig, renderer: renderer,
                            behavioralAxisRuns: cases != nil)
    }
}
