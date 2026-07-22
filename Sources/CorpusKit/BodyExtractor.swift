import Foundation
import ProjectKit

/// Reads a session's touched files into bundle bodies — the `[path: contents]` map that becomes
/// `BundleText.bodies`. Extracted from `CaptureCommand` (plan 013, review round 11 / Option B) so its
/// confinement + safe-read rules are unit-testable in CorpusKit rather than only through capture's
/// integration path.
public enum BodyExtractor {
    /// Read each `touched` path under `workspace`, keeping only what is safe to commit into an evidence
    /// bundle. A file is **skipped** (never fatal) unless it:
    ///   - stays confined under `workspace` and crosses **no symlink** — a session that created a symlink,
    ///     or wrote under a symlinked directory, must not siphon host files (`/etc/passwd`, `~/.ssh/*`, …)
    ///     into the bundle (`firstSymlinkOnPath` returns non-nil on escape OR any symlink component);
    ///   - is a **regular** file with link count 1 — skip FIFO/socket/device (a `FileHandle` read blocks
    ///     forever) and hard links (another inode, possibly a host file outside the workspace);
    ///   - is ≤ 1 MiB and decodes as text — binary / oversized / undecodable content is dropped.
    /// The whole policy is the shared `SafeFile.readConfinedRegularText` helper (round 17): confinement
    /// below `workspace` + the guard order the run stager uses (symlink → regular → hard-link → bounded
    /// → decode), so this reader can't drift out of sync with the other untrusted-read sites.
    public static func extract(touched: Set<String>, workspace: URL) -> [String: String] {
        var out: [String: String] = [:]
        for path in touched.sorted() {
            let url = workspace.appendingPathComponent(path)
            guard case let .success(text) = SafeFile.readConfinedRegularText(url, base: workspace, cap: 1 << 20) else { continue }
            out[path] = text
        }
        return out
    }
}
