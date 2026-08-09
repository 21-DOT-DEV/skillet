import Foundation
import EDDCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Filesystem-confinement + safe-read primitives — the single source of truth for "is this a
/// symlink / hidden / confined below a base?", and for a size-capped UTF-8 read. Shared by the run
/// stager (RunKit's `WorkspaceManager`), the bundle rules/audit (HarnessKit's `SkillBundleRules` /
/// `SkillBundleAudit`), and the deterministic scorers (ScoreKit). Foundation plus ProjectKit stays
/// `EDDCore`-only, so every consumer depends on it *downward* (no dependency cycle) — which is what
/// lets a declined read build the error a command throws, right here beside the refusal itself. Extracted here
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

    /// True iff `url` is confined under `base`, no component from `base` down to `url` is a symlink, and
    /// `url` nests none. Confinement + the path-symlink walk are delegated to ``firstSymlinkOnPath`` (T9:
    /// realpath-canonical, so a *sibling-prefix* like `dir` vs `database` can't be confused — the old raw
    /// `dropFirst(base.path.count)` split lacked a folder-boundary check, the classic partial-path-traversal
    /// bug, [CodeQL java/partial-path-traversal]); the subtree scan stays here. One escape-check, not two.
    public static func noSymlink(at url: URL, under base: URL) -> Bool {
        firstSymlinkOnPath(from: base, to: url) == nil && firstSymlink(in: url) == nil
    }

    /// The first symlink at or under `url` (recursively), or `nil` if the subtree is symlink-free.
    public static func firstSymlink(in url: URL) -> URL? {
        if isSymlink(url) { return url }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return nil }
        for case let child as URL in enumerator where isSymlink(child) { return child }
        return nil
    }

    /// The first symlink among the path components from `base` (exclusive) down to `target`
    /// (inclusive), or `nil` if every component is a real entry (a benign `..` that stays under `base`
    /// is fine). Returns `target` when the path escapes `base` — not under it at all, or a `..` that
    /// pops above it — so callers treat "not confined" like "blocked". `.`/`..` are resolved
    /// **lexically** (round 14), never via `URL.appendPathComponent`'s implementation-defined `..`
    /// handling; any symlink is still caught before a later `..` could pop it.
    public static func firstSymlinkOnPath(from base: URL, to target: URL) -> URL? {
        // ESCAPE CHECK (T9): compare in **confinement-canonical** form — the OS-resolved real path of the
        // longest existing ancestor plus the not-yet-created tail as text — instead of
        // `standardizedFileURL`, whose `/private`-style symlink stripping is *existence-dependent* on
        // Darwin, so a real base and a not-yet-created target could be compared in mismatched forms and a
        // real escape slip through. Canonicalize-then-confine done right for a missing tail (CERT FIO02-C);
        // because `realpath` follows every link, this also catches a suffix symlink that resolves OUTSIDE
        // base. Both sides go through the same routine, so the prefix test is sound on every platform.
        let baseCanon = confinementCanonical(base)
        let targetCanon = confinementCanonical(target)
        let canonPrefix = baseCanon.hasSuffix("/") ? baseCanon : baseCanon + "/"   // root "/" stays "/", not "//"
        guard targetCanon == baseCanon || targetCanon.hasPrefix(canonPrefix) else { return target }   // escapes base
        // SYMLINK WALK: still walk the **raw, non-standardized** components between base and target,
        // lstat-checking each in order. This flags ANY symlink component — even one that stays under base
        // (which the escape check passes) — and, by walking the raw suffix, catches a `..` placed *after* a
        // symlink (`link/../real` routes through `link` though it lexically collapses to `real`). `.`/`..`
        // resolve lexically (round 14).
        //
        // **Where the base sits is settled by asking the filesystem, not by comparing text.** This used
        // to require one path string to start with the other, and answer "no symlink here" when it did
        // not. Two spellings of one folder are ordinary — on this platform `/tmp` is itself a pointer to
        // `/private/tmp` — so a base written one way and a target written the other skipped the walk
        // entirely and reported clean. Measured: with a real symlink inside the folder, `/tmp/x` flagged
        // it and `/private/tmp/x` reported nothing. That is the fail-open shape OWASP names — a check
        // that cannot run must deny, never permit — and it was permitting.
        //
        // Identity, not spelling: two paths name the same directory when the filesystem gives them the
        // same device and file number, which is immune to case, to `/private`, and to any other alias.
        // The walk itself must stay on the path **as written**, because a resolved path has its pointers
        // already followed and so can never contain one (CERT FIO16-J's trap).
        // Three outcomes, not two. A folder that is **absent** and one we **could not look at** are
        // different: nothing can exist below a folder that is not there, so there is no pointer to find
        // and a clean answer is the true one — callers legitimately ask about paths not yet created. But
        // a folder we were refused sight of might hold anything, and that is the case that must refuse.
        // Collapsing them broke a caller asking about a path under a folder that does not exist yet.
        let baseID: FileIdentity
        switch locate(base) {
        case let .at(identity): baseID = identity
        case .absent: return nil
        case .unreadable: return target
        }
        var walked = URL(fileURLWithPath: "/")
        var insideBase = identity(of: walked) == baseID
        var depthInside = 0
        var reachedBase = insideBase
        for raw in target.path.split(separator: "/") {
            let component = String(raw)
            if component == "." { continue }
            if component == ".." {
                if insideBase {
                    if depthInside == 0 { return target }   // pops above base → escape
                    depthInside -= 1
                }
                walked = walked.deletingLastPathComponent()
                insideBase = insideBase || identity(of: walked) == baseID
                continue
            }
            walked = walked.appendingPathComponent(component)
            // Only components *below* the base are ours to judge. Above it is the machine's own layout —
            // a home directory reached through a pointer is not this project's business.
            if insideBase {
                depthInside += 1
                if isSymlink(walked) { return walked }
            } else if identity(of: walked) == baseID {
                insideBase = true
                reachedBase = true
            }
        }
        // Never found the base among the ancestors, so nothing was actually checked. Refuse rather than
        // report clean — the whole point of the change above.
        guard reachedBase else { return target }
        return nil
    }

    /// What the filesystem calls this thing: its device and file number, or `nil` if it cannot be read.
    /// Two paths naming one directory give the same pair however each is spelled. Deliberately follows
    /// pointers, because the question here is "is this the same folder", not "is this a pointer" — that
    /// second question is asked separately, component by component, on the path as written.
    static func identity(of url: URL) -> FileIdentity? {
        if case let .at(found) = locate(url) { return found }
        return nil
    }

    /// What the filesystem says about a path: which thing it is, that there is nothing there, or that we
    /// were not allowed to find out. The third is the one worth keeping separate — it is the only one
    /// where a clean answer would be a guess.
    enum Located {
        case at(FileIdentity)
        case absent
        case unreadable
    }

    static func locate(_ url: URL) -> Located {
        var info = stat()
        if stat(url.path, &info) == 0 { return .at(FileIdentity(device: info.st_dev, number: info.st_ino)) }
        return errno == ENOENT || errno == ENOTDIR ? .absent : .unreadable
    }

    /// A directory's device and file number. Named rather than a pair of numbers so it can be compared
    /// directly, including when one side is missing because the path could not be read.
    struct FileIdentity: Equatable {
        let device: dev_t
        let number: ino_t
    }

    /// The confinement-canonical form of `url` (T9): the OS-resolved real path (`realpath` — every symlink
    /// followed) of its longest EXISTING ancestor, with the not-yet-created remainder re-attached as plain
    /// text. `realpath` alone fails on a missing tail; `standardizedFileURL` resolves `/private`-style
    /// links only for existing paths — so neither is a sound canonical form for a path being *created*.
    /// This is the pair fed to both sides of a confinement prefix test (CERT FIO02-C canonicalize-then-confine).
    static func confinementCanonical(_ url: URL) -> String {
        var existing = url.standardizedFileURL   // resolve ./.. lexically first (no filesystem)
        var trailing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path) {
            let parent = existing.deletingLastPathComponent()
            if parent.path == existing.path { break }   // reached the filesystem root
            trailing.insert(existing.lastPathComponent, at: 0)
            existing = parent
        }
        var result = realpathString(existing.path) ?? existing.path
        for component in trailing { result += result.hasSuffix("/") ? component : "/" + component }
        return result
    }

    /// `realpath(3)` as a String, or `nil` if it fails (e.g. a permission error on an ancestor).
    static func realpathString(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Why one plain-file read was refused — each case carries the human phrase the caller's
    /// disclosure/error should include, so refusal messages can't drift between call sites.
    public enum SafeReadRefusal: Error, Equatable, Sendable {
        case notFound
        case symlink
        case notRegularFile
        case hardLink
        case unconfined
        case unreadable
        case oversized(size: Int, cap: Int)
        case binary

        public var reason: String {
            switch self {
            case .notFound: "not found"
            case .symlink: "is a symlink — not followed"
            case .notRegularFile: "is not a regular file (directory/FIFO/socket/device) — not read"
            case .hardLink: "is a hard link (linked inode) — not read"
            case .unconfined: "escapes its base directory (a symlink on the path, or a `..` escape) — not read"
            case .unreadable: "unreadable (permissions or I/O error)"
            case let .oversized(size, cap): "is \(size) bytes — exceeds the \(cap >> 20) MiB read cap"
            case .binary: "is not UTF-8 text"
            }
        }

        /// What to actually do about it. Lives here because the refusal is the only thing that knows
        /// which of these happened: callers turn several of these into one "this file is invalid" error,
        /// whose standard advice is *"fix or regenerate the file so it matches its schema"* — right for a
        /// file whose contents are the wrong shape, and wrong for every case below. Being told to correct
        /// a file's contents when the actual problem is that the path points somewhere else, or that a
        /// directory sits where a file belongs, sends you looking where the problem is not.
        public var fix: String {
            switch self {
            case .notFound:
                "create it, or point the command at a file that exists"
            case .symlink, .unconfined:
                "replace the symbolic link with the real file — a link could reach outside the project, where the checks that keep this undoable do not apply"
            case .notRegularFile:
                "put an ordinary file there — a directory or a pipe cannot be read as one"
            case .hardLink:
                "replace it with an independent copy; a second name for the same file can be changed from outside the project"
            case .unreadable:
                "check the file's permissions and that the disk is readable, then re-run"
            case let .oversized(_, cap):
                "split it, or bring it under the \(cap >> 20) MiB limit"
            case .binary:
                "save it as UTF-8 text — this is read as text, not as binary data"
            }
        }

        /// Turn a declined read into the error a command throws, **carrying the matching advice with it**.
        ///
        /// This exists because remembering to attach the advice at each call site did not work: six
        /// places turn a declined read into this error, the advice was added at two of them, and the
        /// other four went on telling people to fix a file's contents when the problem was that the path
        /// pointed outside the project. One route means there is nothing left to remember, and a seventh
        /// caller cannot repeat the omission.
        ///
        /// `saying` prefixes the reason where a call site names what it was reading ("canned reply …"),
        /// which is information the refusal itself does not have.
        public func rejection(path: String, saying prefix: String = "") -> EDDError {
            .invalidArtifact(path: path, reason: prefix.isEmpty ? reason : "\(prefix)\(reason)", fix: fix)
        }
    }

    /// The **one sanctioned way to read a file whose bytes an outsider could control** (a cloned repo,
    /// a captured session, an operator-supplied path). Bundles the untrusted-read guard set the F33
    /// security pass consolidated (its absence at individual call sites caused three review-round
    /// escapes in a row): symlink lstat first (never followed), regular-file only (a FIFO/socket open
    /// blocks forever — CERT FIO32-C), single link (`linkCount > 1` = another inode, possibly outside
    /// the project — CWE-62), and a bounded read (no unbounded slurp). Callers keep their own policy
    /// (throw / disclose / skip) and their own *path confinement* of the parent directory.
    public static func readPlainData(_ url: URL, cap: Int) -> Result<Data, SafeReadRefusal> {
        guard !isSymlink(url) else { return .failure(.symlink) }
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.notFound) }
        guard isRegularFile(url) else { return .failure(.notRegularFile) }
        guard linkCount(url) == 1 else { return .failure(.hardLink) }
        guard let (data, fullSize) = boundedRead(url, cap: cap) else { return .failure(.unreadable) }
        guard fullSize <= cap else { return .failure(.oversized(size: fullSize, cap: cap)) }
        return .success(data)
    }

    /// ``readPlainData(_:cap:)`` + strict UTF-8 decode (binary rejected) — for the text formats
    /// (YAML/markdown); JSON readers take the data variant straight into their decoder.
    public static func readPlainText(_ url: URL, cap: Int) -> Result<String, SafeReadRefusal> {
        readPlainData(url, cap: cap).flatMap { data in
            guard let text = decodeText(data, truncated: false) else { return .failure(.binary) }
            return .success(text)
        }
    }

    /// ``readPlainText(_:cap:)`` **plus path-confinement below `base`**: refuses the read if any
    /// component from `base` down to `url` is a symlink, or if the path escapes `base` at all (via
    /// `firstSymlinkOnPath`), before any bytes are read. This is the one call for "read an untrusted file
    /// at a path an outsider influenced **and** prove it stays inside a directory I control" — it folds
    /// the pre-read confinement the evidence-body reader (`BodyExtractor`) used to hand-roll ahead of the
    /// plain read into the same sanctioned path, so that reader can't drift out of sync with the others.
    public static func readConfinedRegularText(_ url: URL, base: URL, cap: Int) -> Result<String, SafeReadRefusal> {
        guard firstSymlinkOnPath(from: base, to: url) == nil else { return .failure(.unconfined) }
        return readPlainText(url, cap: cap)
    }

    /// Read up to `cap` bytes without slurping a huge file whole; also returns the file's full byte
    /// size (from metadata) so truncation can be disclosed precisely. `nil` if unreadable.
    public static func boundedRead(_ url: URL, cap: Int) -> (data: Data, fullSize: Int)? {
        // Open with **O_NOFOLLOW** so a symlink swapped in at the final path component *after* the caller's
        // pre-open lstat fails the open itself — closing the check-then-open (TOCTOU) race for the symlink
        // vector by construction (CERT POS35-C / FIO45-C), and **O_NONBLOCK** so a special-file swap can't
        // block the open (CERT FIO32-C). The pre-open guards in `readPlainData` stay as the static layer;
        // O_NOFOLLOW protects only the final component, so a symlinked *parent* still relies on the
        // path-walk guard, and the residual — a regular file swapped for another regular file mid-run — is
        // the accepted floor (round 16, A+). O_NONBLOCK is harmless for a regular-file read (always ready).
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        // Verify the **open descriptor itself** is a regular file (CERT FIO45-C): a special file
        // (FIFO/socket/device) swapped in during the caller's pre-check → open gap is refused here —
        // `fstat` refers to exactly what was opened, not the path, so O_NONBLOCK letting the open succeed
        // can't turn a swapped-in pipe into an "empty file". Closes the special-file TOCTOU by construction;
        // the regular-file-for-regular-file swap stays the accepted floor (round 16).
        var st = stat()
        guard fstat(fd, &st) == 0, (UInt32(st.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFREG) else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
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
        return (data, resolveFullSize(sizeAttr: sizeAttr, dataCount: data.count, cap: max(cap, 0)))
    }

    /// The reported full size when the after-read `stat` may have failed (round 11: the old
    /// `?? data.count` fallback always passed callers' `fullSize <= cap` checks, so an oversized file
    /// whose stat failed mid-race returned **truncated as success**). Provable rule, not blanket
    /// refusal: a read that came in UNDER the cap hit EOF — the bytes in hand are the whole file, so
    /// `dataCount` is exact even for a file deleted after open. A read that FILLED the cap with no
    /// verifiable size cannot prove there wasn't more — report just past the cap so every caller
    /// refuses (fail closed exactly where proof is impossible; CWE-367 TOCTOU / CERT FIO45-C).
    static func resolveFullSize(sizeAttr: Any?, dataCount: Int, cap: Int) -> Int {
        if let sized = (sizeAttr as? UInt64).map({ Int(clamping: $0) }) ?? (sizeAttr as? Int) { return sized }
        if dataCount < cap { return dataCount }
        return cap == Int.max ? Int.max : cap + 1
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
