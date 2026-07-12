import Foundation

/// Filesystem-confinement + safe-read primitives — the single source of truth for "is this a
/// symlink / hidden / confined below a base?", and for a size-capped UTF-8 read. Shared by the run
/// stager (RunKit's `WorkspaceManager`), the bundle rules/audit (HarnessKit's `SkillBundleRules` /
/// `SkillBundleAudit`), and the deterministic scorers (ScoreKit). Pure Foundation — ProjectKit stays
/// `EDDCore`-only, so every consumer depends on it *downward* (no dependency cycle). Extracted here
/// (F17) from `SkillBundleRules`/`WorkspaceManager`; those keep thin delegating wrappers so their
/// callers don't churn.
public enum SafeFile {
    /// Whether `url` is itself a symbolic link (lstat semantics — does not follow the link).
    /// Symlinks are the escape/leak guard: staging drops them; scoring never follows them.
    public static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// Whether a path component is hidden (`.git`/`.env`/`.skillet`/…) — a leading dot.
    public static func isHidden(_ name: String) -> Bool {
        name.hasPrefix(".")
    }

    /// Whether `url` is a **regular** file (from its metadata). A non-regular special file (FIFO / socket
    /// / device) must never be opened with a `FileHandle` — the read blocks forever. `false` if unreadable.
    public static func isRegularFile(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType) == .typeRegular
    }

    /// The hard-link count (`.referenceCount`), defaulting to 1. `> 1` means another directory entry
    /// points at the same inode — possibly a host file outside the sandbox (a same-fs hard link).
    public static func linkCount(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.referenceCount]) as? Int) ?? 1
    }

    /// True iff no component from `base` down to `url` is a symlink, and `url` nests none.
    public static func noSymlink(at url: URL, under base: URL) -> Bool {
        var walk = base
        for component in url.path.dropFirst(base.path.count).split(separator: "/") {
            walk.appendPathComponent(String(component))
            if isSymlink(walk) { return false }
        }
        return firstSymlink(in: url) == nil
    }

    /// The first symlink at or under `url` (recursively), or `nil` if the subtree is symlink-free.
    public static func firstSymlink(in url: URL) -> URL? {
        if isSymlink(url) { return url }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return nil }
        for case let child as URL in enumerator where isSymlink(child) { return child }
        return nil
    }

    /// The first symlink among the path components from `base` (exclusive) down to `target`
    /// (inclusive), or `nil` if every component is a real entry. Returns `target` when it is not under
    /// `base` at all (an escape), so callers treat "not confined" like "blocked".
    public static func firstSymlinkOnPath(from base: URL, to target: URL) -> URL? {
        let basePath = base.standardizedFileURL.path
        let targetStd = target.standardizedFileURL.path
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"   // root "/" stays "/", not "//"
        guard targetStd == basePath || targetStd.hasPrefix(prefix) else { return target }   // not under base → escape
        // Walk the **non-standardized** suffix so a `..` *after* a symlink is still visited. Standardizing
        // first (as the escape guard above does) collapses `link/..`, hiding the `link` symlink — a
        // path-traversal bypass: `skills_root: link/../real` would create/read *through* `link` while both
        // the lexical guard and a standardized walk see only `.../real`. Each component is lstat-checked in
        // order, so a symlink is caught before its trailing `..` is ever reached.
        let rawTarget = target.path
        let suffix = rawTarget.hasPrefix(basePath) ? String(rawTarget.dropFirst(basePath.count))
                                                   : String(targetStd.dropFirst(basePath.count))
        var walk = base.standardizedFileURL
        for component in suffix.split(separator: "/") where component != "." {
            walk.appendPathComponent(String(component))
            if isSymlink(walk) { return walk }
        }
        return nil
    }

    /// Read up to `cap` bytes without slurping a huge file whole; also returns the file's full byte
    /// size (from metadata) so truncation can be disclosed precisely. `nil` if unreadable.
    public static func boundedRead(_ url: URL, cap: Int) -> (data: Data, fullSize: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // `read(upToCount:)` returns nil ONLY at EOF; it *throws* on a genuine I/O error (EIO/EINTR/EBADF).
        // A `try?` would flatten both into `Data()`, so an unreadable file would look like an empty one —
        // callers (extractBodies, ScoreRunner's SKILL-S000) could then store/score "" instead of skipping
        // or reporting it. Coalesce only EOF; surface a real error as `nil`.
        let data: Data
        do { data = try handle.read(upToCount: max(cap, 0)) ?? Data() }
        catch { return nil }
        // True byte size (for truncation disclosure). `.size` is an NSNumber — read it as UInt64 and
        // *clamp* into Int, so a size > Int.max reports as `Int.max` (⇒ flagged oversized) rather than
        // falling back to the capped `data.count` and slipping past a caller's oversized-file guard.
        let sizeAttr = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size]
        let fullSize = (sizeAttr as? UInt64).map { Int(clamping: $0) } ?? (sizeAttr as? Int) ?? data.count
        return (data, fullSize)
    }

    /// Decode `data` as UTF-8 text, or `nil` for binary. A NUL byte ⇒ binary. When `truncated` (the
    /// read hit the cap), a trailing *incomplete* multi-byte sequence is trimmed before the final
    /// decode so a boundary cut isn't misread as binary; a genuinely invalid byte (e.g. `0xFF` that is
    /// not a boundary artifact) still falls through to `nil`.
    ///
    /// Known heuristic limitation (accepted): with an absurdly small cap (< one scalar, ~4 bytes), a
    /// prefix of only stray continuation bytes can trim to empty and read as empty text. Unreachable at
    /// the shipped caps — a genuinely binary file's first bytes carry a NUL or a non-continuation
    /// invalid byte and fail to binary.
    public static func decodeText(_ data: Data, truncated: Bool) -> String? {
        if data.contains(0) { return nil }
        if let whole = String(bytes: data, encoding: .utf8) { return whole }
        guard truncated else { return nil }   // invalid UTF-8 that isn't a boundary cut ⇒ binary
        var d = data
        var trimmedContinuations = 0
        while let last = d.last, (last & 0b1100_0000) == 0b1000_0000, trimmedContinuations < 3 {
            d.removeLast(); trimmedContinuations += 1
        }
        if let last = d.last, ((0xC2 as UInt8)...(0xF4 as UInt8)).contains(last) { d.removeLast() }   // a genuine incomplete lead byte only
        return String(bytes: d, encoding: .utf8)   // still invalid ⇒ binary
    }
}
