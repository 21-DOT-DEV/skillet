import Foundation
import EDDCore
import HarnessKit

extension SuggestCommand {
    /// **The charter's rule, implemented literally:** the only sanctioned way to edit a live skill file
    /// *"refuses a dirty tree and stops short of the commit"*. Whole-tree is the plain reading of that,
    /// and it needs no amendment.
    ///
    /// The reason is that your version-control history **is** the undo button for what this command
    /// writes. That only holds if everything uncommitted afterwards is the tool's work — otherwise
    /// reverting its change also throws away yours.
    ///
    /// Anything modified, staged, or untracked counts. Files git is told to ignore do not, which is why
    /// drafting into the ignored scratch folder never blocks the apply that follows it.
    ///
    /// *If this proves obstructive in practice*, the amendment to propose is **recoverability** —
    /// permit already-staged work, which a single checkout restores, and refuse untracked targets,
    /// which nothing restores. Bring evidence and amend; do not quietly relax the check.
    // (An `assertCleanRepository` wrapper lived here briefly. It had no callers once the preview needed
    // the fact rather than the reaction, so it went; the two pieces below are what is actually used.)

    /// The question that actually matters before overwriting something: **can this exact file be brought
    /// back afterwards?**
    ///
    /// The whole-project check above answers a proxy for it, and that proxy can be muted several ways —
    /// the setting that hides untracked files, a folder listed in the project's ignore file, or a per-file
    /// marker meaning "pretend this hasn't changed". Each was reproduced overwriting work irrecoverably.
    /// The recognised shape for an irreversible operation is to validate the target and confirm an undo
    /// path exists, rather than infer both from ambient state — so this asks version control directly.
    ///
    /// This makes the tool's own closing advice true: it tells you to review the change and commit it,
    /// which assumes version control has your back. For a file it has never seen, it does not.
    /// **Three answers, not two.** "Yes it is tracked", "no it is not", and "I could not find out" are
    /// different, and the third used to be split across the other two by accident: a missing `git`
    /// returned "no objection" and let the write through, while a `git` that failed to launch or timed
    /// out produced a refusal claiming your file was not in version control. Being unable to evaluate a
    /// safety check is its own outcome; it stops the write, like every other check here, but says so
    /// truthfully rather than asserting something it never established.
    ///
    /// Throwing marks that third case, which reports as a problem with your machine or tools — the same
    /// classification the neighbouring check already uses when `git` cannot be found.
    static func untrackedFileRefusal(_ relativePath: String, root: URL) async throws -> Disclosure? {
        guard let git = BinaryResolver().resolve(flag: nil, envVar: "SKILLET_GIT_BIN",
                                                 configPath: nil, pathName: "git")?.path else {
            throw EDDError.harnessNotFound(
                harness: "git",
                reason: "whether \(relativePath) is in version control could not be checked, and that is what makes this change undoable")
        }
        let listed: ProcessOutput
        switch await SubprocessLauncher().describedRun(
            git, ["ls-files", "--error-unmatch", "--", relativePath], workingDirectory: root) {
        case let .success(output):
            listed = output
        case let .failure(why):
            throw EDDError.harnessNotFound(
                harness: "git",
                reason: "`git ls-files` in \(root.path) \(why.plainly), so whether \(relativePath) is in version control is unknown")
        }
        guard listed.exitCode != 0 else { return nil }
        // Non-zero is what this command reports for a path it does not track — but only say so when git
        // says so. Any other failure is the third case again, not an answer.
        let said = listed.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard said.localizedCaseInsensitiveContains("did not match") || said.isEmpty else {
            throw EDDError.harnessNotFound(
                harness: "git",
                reason: "`git ls-files` failed (exit \(listed.exitCode))\(said.isEmpty ? "" : ": \(said)"), so whether \(relativePath) is in version control is unknown")
        }
        return Disclosure(
            subject: relativePath,
            reason: "is not in version control, so this change could not be undone — commit it first")
    }

    static func dirtyRepositoryError(_ dirt: Disclosure) -> EDDError {
        .gate(message: "\(dirt.reason), so nothing was written",
              remedy: "commit or stash everything first; that way `git diff` afterwards is exactly what this command changed, and reverting it is one command")
    }

    /// The **fact**: what is uncommitted, or `nil` when the repository is clean. Separated from the
    /// reaction because a preview reports it and carries on collecting other blockers, while a run that
    /// is about to write must stop here.
    ///
    /// Not being able to *ask* the question — no `git`, or no repository — still throws in both modes.
    /// There is no useful preview of "would this succeed?" when the check that decides it cannot run.
    static func repositoryDirt(root: URL) async throws -> Disclosure? {
        guard let git = BinaryResolver().resolve(flag: nil, envVar: "SKILLET_GIT_BIN",
                                                 configPath: nil, pathName: "git")?.path else {
            throw EDDError.harnessNotFound(
                harness: "git",
                reason: "applying needs version control, because reverting the change it makes is how you undo it")
        }
        // `--untracked-files=all` is passed explicitly because the setting `status.showUntrackedFiles=no`
        // — which people turn on to make git faster — otherwise makes this report a clean tree while
        // untracked work sits right there. A safety gate whose answer depends on an unrelated preference
        // is not a gate. Verified: with that setting, a plain status printed nothing and the tool
        // overwrote a file version control could not bring back.
        let output: ProcessOutput
        switch await SubprocessLauncher().describedRun(
            git, ["status", "--porcelain", "--untracked-files=all"], workingDirectory: root) {
        case let .success(result):
            output = result
        case let .failure(why):
            throw EDDError.harnessNotFound(harness: "git", reason: "`git status` in \(root.path) \(why.plainly)")
        }
        guard output.exitCode == 0 else {
            // `git status` fails non-zero for *any* problem — a damaged repository, a permissions error,
            // a lock held by another process. Reporting all of them as "you are not in a repository"
            // gives a confident wrong diagnosis and sends you after the wrong remedy. git's own words are
            // authoritative and always accurate, so lead with them; keep the tailored explanation only
            // when git itself says that is the cause.
            let said = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let notARepository = said.localizedCaseInsensitiveContains("not a git repository")
            throw EDDError.harnessNotFound(
                harness: "git",
                reason: notARepository
                    ? "this project is not inside a git repository, so there would be no way to undo the change"
                    : "`git status` failed (exit \(output.exitCode))\(said.isEmpty ? "" : ": \(said)")")
        }
        let dirty = output.stdout.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !dirty.isEmpty else { return nil }
        let shown = dirty.prefix(5).map { $0.trimmingCharacters(in: .whitespaces) }
        let more = dirty.count > 5 ? " (and \(dirty.count - 5) more)" : ""
        return Disclosure(subject: "repository",
                          reason: "has uncommitted changes — \(shown.joined(separator: ", "))\(more)")
    }
}

/// How long a version-control command gets before the tool stops waiting.
///
/// The check normally costs almost nothing — measured at 0.01 seconds on a 260-file project — so the
/// limit exists only for the slow case, and that is the case it has to be sized for. The published
/// worst case for this command is around 18 seconds, of which 6 is spent listing files version control
/// has never seen. This tool asks for that listing **on purpose**: without it, a setting people enable
/// to make version control faster hid unsaved work and the tool overwrote it. So the expensive mode is
/// deliberate, and the limit needs headroom over the slow case rather than over the fast one.
///
/// The two harms are not equal. Waiting longer on a very large project is an annoyance; being refused a
/// write that would have succeeded means the command does not work for you at all. Hence a limit well
/// clear of anything reported in the wild, plus a way to raise it — the usual shape for this, and the
/// same shape as the other `SKILLET_*` settings here.
///
/// There is deliberately **no** value meaning "wait forever". A safety check you cannot rely on
/// finishing is not one you can build an irreversible write on top of.
enum GitPatience {
    static let variable = "SKILLET_GIT_TIMEOUT_SECONDS"
    static let fallbackSeconds = 120

    /// The configured limit, or the default when the setting is absent, unreadable, or not a positive
    /// whole number. A junk value is not honoured as "no limit" and does not stop the command either —
    /// silently ignoring it leaves the safe default in place, which is the conservative direction.
    static var seconds: Int {
        guard let raw = ProcessInfo.processInfo.environment[variable],
              let parsed = Int(raw.trimmingCharacters(in: .whitespaces)), parsed > 0 else {
            return fallbackSeconds
        }
        return parsed
    }
}

/// Why a version-control command produced no answer. **Running out of time is its own outcome.**
///
/// These used to collapse into one: every failure became "could not be run", so a project too large for
/// the time limit and a `git` that cannot start read identically, while the fixes for them share
/// nothing. Keeping them apart is the ordinary treatment — the well-known trap is a launch failure
/// surfacing as a timeout, which sends you tuning limits when the program was never going to run.
enum GitFailure: Error {
    case ranOutOfTime(seconds: Int)
    /// The system's own words. Better than any sentence written in advance, because the causes here —
    /// not executable, working folder gone, out of process handles — are the operating system's to name.
    /// Interpolated rather than asked for a "localized description": these errors carry no translation,
    /// so that route returns the placeholder "The operation couldn\u2019t be completed", which names
    /// nothing and is worse than the fixed sentence it replaced.
    case couldNotRun(said: String)

    /// The clause that slots into "…, so whether X is in version control is unknown".
    var plainly: String {
        switch self {
        case let .ranOutOfTime(seconds):
            "took longer than \(seconds)s and was stopped (raise it with \(GitPatience.variable) if this project is large)"
        case let .couldNotRun(said):
            "could not be run: \(said)"
        }
    }
}

extension SubprocessLauncher {
    /// A launch whose failure is **described** rather than reduced to "nothing happened".
    func describedRun(_ executable: String, _ arguments: [String],
                      workingDirectory: URL) async -> Result<ProcessOutput, GitFailure> {
        do {
            return .success(try await run(executable, arguments, workingDirectory: workingDirectory.path,
                                          timeout: .seconds(GitPatience.seconds), environment: nil,
                                          outputLimitBytes: 1 << 20))
        } catch is ProcessError {
            // The only thing the launcher itself raises, and only for the watchdog firing.
            return .failure(.ranOutOfTime(seconds: GitPatience.seconds))
        } catch {
            return .failure(.couldNotRun(said: "\(error)"))
        }
    }
}
