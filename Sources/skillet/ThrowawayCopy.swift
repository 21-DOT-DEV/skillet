import Foundation
import EDDCore
import HarnessKit
import RenderKit
import ProjectKit

/// A disposable copy of the repository, made to measure an edit without touching anything you own.
///
/// **Attached to no branch.** Asking for a copy without naming a starting point creates a branch named
/// after the folder, which then has to be deleted separately — leave that step out and branches pile up
/// invisibly, each holding a name nothing else can check out. There is no use for one here: a branch
/// exists so you can commit from the copy, and landing an edit goes through the command that writes your
/// working tree instead. A copy attached to nothing also cannot collide with a branch already in use.
///
/// **Removal is forced, and that is bounded.** Applying the edit is exactly what makes the copy differ
/// from the committed state, so the plain removal refuses every time it matters. The usual caution about
/// forcing a delete does not leave this exposed: git refuses to force-remove any path that is not one of
/// its own registered copies, so the reach is limited to copies this repository made.
enum ThrowawayCopy {
    /// Where the copies live — outside your repository, so running this never makes your own tree look
    /// modified, and never leaves debris inside a project you are about to inspect.
    /// **The name is checked here, not only where it came from.** This builds a folder name by pasting
    /// the skill's name into it, so a name carrying a path separator followed by a step upwards stops
    /// being one folder and becomes a route out: measured, `a/../../b` lands beside the whole temporary
    /// area rather than inside it. The run then creates that folder and later force-deletes it.
    ///
    /// It cannot be reached today — a name is matched against folders actually on disk first, and no real
    /// folder name contains a separator — but the guidance for names that become paths is to check where
    /// the value is *used* rather than trust the one caller that happens to check it, because a single
    /// check is a single point of failure and this is reachable by any caller.
    ///
    /// **Two checks, because the first one alone is only as good as the list behind it.** Refusing known
    /// spellings depends on having thought of them: a name of `..` on its own stays inside, which is what
    /// led a review to conclude escape was impossible. Confirming where the finished path actually landed
    /// does not depend on anyone having anticipated the spelling.
    static func location(for skill: String) throws -> URL {
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        guard SafeFile.isSingleSafeComponent(skill) else {
            throw EDDError.usage(
                message: "the skill name '\(skill)' cannot be used to name a working folder",
                remedy: "a skill's name is a single folder name — it cannot be empty, contain a path "
                    + "separator, or be a step upwards")
        }
        let built = Self.build(temporary: temporary, skill: skill)
        guard SafeFile.isConfined(built, to: temporary) else {
            throw EDDError.usage(
                message: "the working folder for '\(skill)' would sit outside the temporary area",
                remedy: "use a skill whose name is a plain folder name")
        }
        return built
    }

    /// **Builds from the folder it was handed, not from the one it could look up itself.** It ignored the
    /// argument and fetched the temporary folder again, so the check that the finished path stays inside
    /// that folder was comparing a path against the very thing it was built from — true by construction
    /// rather than by checking. It still caught a name that walks out, because that comes from the name
    /// rather than the base; but the moment anything passed a different folder, the check would have
    /// agreed with itself and let the path escape.
    private static func build(temporary: URL, skill: String) -> URL {
        temporary
            // **The whole identifier, not a prefix of it.** Eight hex characters is a birthday bound, and
            // while a clash fails safe — making the copy would error rather than reuse someone else's —
            // there is no reason to keep the bound. Same reasoning that widened the ending on a test's
            // generated name.
            .appendingPathComponent("skillet-iterate-\(skill)-\(UUID().uuidString)", isDirectory: true)
    }

    /// **Make a copy, do the work, always remove the copy.** The removal is *waited for* on the way out
    /// of a success and on the way out of a failure alike — which is the whole reason this exists as a
    /// scope rather than a line the caller must remember.
    ///
    /// **What went wrong without it.** Cleanup sat in an on-the-way-out block, and a block like that
    /// cannot wait for slow work in this compiler, so it started the removal and returned; the program
    /// could exit first. That left both the folder on disk and a dead entry in git's list of copies —
    /// and a dead entry does *not* clear itself when the next copy is made, which was measured: git only
    /// sweeps records older than `gc.worktreePruneExpire`, three months by default. So every failed
    /// measurement leaked, and the leaks accumulated for a quarter of a year.
    ///
    /// This is the ordinary scoped-resource shape — a scope owns the thing's lifetime so nobody has to
    /// remember to release it. `keep` means keep: if you asked to inspect the copy, a failure is exactly
    /// when you want it left behind.
    /// Returns what the work produced, and — separately — the copy's path **if it survived when it
    /// should not have**. The caller is expected to say so: deletion can fail on a lock or a permission
    /// problem, and until this returned that fact, the command printed a complete successful report and
    /// exited `0` while leaving both the folder and an entry in git's own list of copies, which does not
    /// clear itself for three months. The routine below even promised in its own comment that the path
    /// was "printed by the caller"; no caller had anything to print it from.
    static func withCopy<T>(of root: URL, for skill: String, keep: Bool,
                            _ body: (URL) async throws -> T) async throws -> (value: T, survived: URL?) {
        let path = try location(for: skill)
        try await create(at: path, root: root)
        do {
            let value = try await body(path)
            let removed = keep ? true : await remove(at: path, root: root)
            return (value, removed ? nil : path)
        } catch {
            if keep {
                // **Asking to keep the copy is why you would want it now.** The copy is deliberately left
                // behind here, and nothing used to say where — so the one case where you most want to look
                // inside it was the case where you could not find it. One line, for the same reason as
                // below: the measurement has already failed and that stays the headline.
                Console.emit(Rendering(stderr: "note: the throwaway copy was kept and is at \(path.path)"
                    + " — `git worktree remove --force \(path.path)` when you are done with it\n"))
            } else if await remove(at: path, root: root) == false {
                // The measurement already failed; losing the copy as well is worth one line, not a
                // second error that would hide the first.
                Console.emit(Rendering(stderr: "note: the throwaway copy could not be removed and is "
                    + "still at \(path.path) — `git worktree remove --force \(path.path)`\n"))
            }
            throw error
        }
    }

    static func create(at path: URL, root: URL) async throws {
        _ = try await git(["worktree", "add", "--detach", path.path, "HEAD"], root: root,
                          whenItFails: "a disposable copy of the repository could not be made")
    }

    /// Best-effort: a failure to tidy up must not turn a finished measurement into an error, so this
    /// reports rather than throws. The path is printed by the caller when it survives.
    @discardableResult
    static func remove(at path: URL, root: URL) async -> Bool {
        ((try? await git(["worktree", "remove", "--force", path.path], root: root,
                         whenItFails: "the disposable copy could not be removed")) != nil)
    }

    private static func git(_ arguments: [String], root: URL, whenItFails: String) async throws -> String {
        guard let binary = BinaryResolver().resolve(flag: nil, envVar: "SKILLET_GIT_BIN",
                                                    configPath: nil, pathName: "git")?.path else {
            throw EDDError.harnessNotFound(harness: "git", reason: whenItFails)
        }
        switch await SubprocessLauncher().describedRun(binary, arguments, workingDirectory: root) {
        case let .success(result) where result.exitCode == 0:
            return result.stdout
        case let .success(result):
            let said = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw EDDError.harnessNotFound(
                harness: "git",
                // **The command as it was actually run, not its first two words.** It used to print only
                // `git worktree add`, dropping the path and the rest — so the reported command was one
                // nobody had run and could not be re-run to see the failure.
                reason: "\(whenItFails) — `git \(arguments.joined(separator: " "))` failed (exit \(result.exitCode))"
                    + (said.isEmpty ? "" : ": \(said)"))
        case let .failure(why):
            throw EDDError.harnessNotFound(harness: "git", reason: "\(whenItFails) — \(why.plainly)")
        }
    }
}
