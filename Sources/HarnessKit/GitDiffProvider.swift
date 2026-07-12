import Foundation

/// Tolerant workspace git-diff provider for `capture` (F26). Extracted from `CaptureCommand` (plan 013,
/// review round 11 / Option B) so its several git-invocation modes — staged-vs-unstaged, unborn-branch
/// fallback, untracked enumeration, path exclusion — are unit-testable in isolation rather than only
/// through the capture integration path.
///
/// Produces the **tracked (staged + unstaged) + untracked** diff plus the set of touched paths, all
/// **workspace-relative** (`--relative`). Any git failure — not a repo, or no `git` resolved — yields an
/// empty diff so capture still produces a bundle (git is best-effort context, not a hard input).
public struct GitDiffProvider {
    let git: String?
    let launcher: any ProcessLauncher

    /// - Parameters:
    ///   - git: resolved `git` binary path, or `nil` (→ empty diff, so capture degrades gracefully).
    ///   - launcher: the sanctioned process launcher (the only way skillet shells out, §11).
    public init(git: String?, launcher: any ProcessLauncher) {
        self.git = git
        self.launcher = launcher
    }

    /// - Parameters:
    ///   - workspace: the directory the session ran in — the diff is scoped + relative to it.
    ///   - excludePrefix: a workspace-relative prefix (the sessions dir, when it lives *inside* the
    ///     workspace) whose paths are dropped from both the diff and the touched set, so prior bundle
    ///     files aren't re-captured into the new one.
    public func diff(workspace: URL, excludePrefix: String?) async -> (diff: String, touched: Set<String>) {
        guard let git else { return ("", []) }
        func run(_ args: [String], accept: Set<Int32>) async -> String? {
            // A real diff can far exceed the launcher's 64 MiB default; cap generously (256 MiB) so a
            // large-but-realistic change isn't silently truncated into an incomplete `.diff` artifact,
            // while still bounding memory. (A pathological >256 MiB diff remains bounded — a documented edge.)
            guard let out = try? await launcher.run(
                git, ["-C", workspace.path] + args, workingDirectory: workspace.path,
                timeout: .seconds(120), environment: nil, outputLimitBytes: 256 << 20),
                  accept.contains(out.exitCode) else { return nil }
            return out.stdout
        }
        func excluded(_ path: String) -> Bool {
            guard let p = excludePrefix, !p.isEmpty else { return false }
            return path == p || path.hasPrefix(p.hasSuffix("/") ? p : p + "/")
        }
        // Exclude the sessions-dir prefix from the diff *command* (a git pathspec), not just the name list
        // — otherwise the tracked-diff string still carries hunks for prior bundle files while `names` /
        // `untracked` drop them (an inconsistent artifact). `:!<prefix>` is cwd-relative, matching
        // `--relative`; `.` keeps the diff scoped to the workspace. The `excluded()` filters below stay as
        // a second layer in case the pathspec ever no-ops.
        let pathspec: [String] = {
            guard let p = excludePrefix, !p.isEmpty else { return [] }
            return ["--", ".", ":!\(p)"]
        }()
        // Tracked changes = working tree vs the last commit (`diff HEAD`) so **staged** modifications and
        // staged-new files are included (the spec's "tracked + untracked"). A plain `git diff` compares
        // only working-tree-vs-index and silently drops staged changes (verified). On an **unborn branch**
        // (no HEAD) `diff HEAD` errors, so fall back to `diff --cached` (index vs the empty tree).
        func trackedDiff(_ extra: [String]) async -> String? {
            if let head = await run(["diff", "HEAD", "--relative", "--no-renames"] + extra + pathspec, accept: [0]) {
                return head
            }
            return await run(["diff", "--cached", "--relative", "--no-renames"] + extra + pathspec, accept: [0])
        }
        guard let tracked = await trackedDiff([]) else { return ("", []) }
        let names = (await trackedDiff(["--name-only", "-z"]) ?? "")
            .split(separator: "\0").map(String.init).filter { !excluded($0) }   // -z: exact filenames (matches ls-files)
        let untracked = (await run(["ls-files", "--others", "--exclude-standard", "-z"], accept: [0]) ?? "")
            .split(separator: "\0").map(String.init).filter { !excluded($0) }
        var combined = tracked
        for path in untracked {
            combined += await run(["diff", "--no-index", "--no-renames", "--", "/dev/null", path], accept: [0, 1]) ?? ""
        }
        return (combined, Set(names + untracked))
    }
}
