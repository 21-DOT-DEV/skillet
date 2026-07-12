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
    /// The ordering mirrors the run stager: symlink → regular → hard-link → bounded read.
    public static func extract(touched: Set<String>, workspace: URL) -> [String: String] {
        var out: [String: String] = [:]
        for path in touched.sorted() {
            let url = workspace.appendingPathComponent(path)
            guard SafeFile.firstSymlinkOnPath(from: workspace, to: url) == nil else { continue }
            guard SafeFile.isRegularFile(url), SafeFile.linkCount(url) == 1 else { continue }
            guard let (data, fullSize) = SafeFile.boundedRead(url, cap: 1 << 20), fullSize <= (1 << 20),
                  let text = SafeFile.decodeText(data, truncated: false) else { continue }
            out[path] = text
        }
        return out
    }
}
