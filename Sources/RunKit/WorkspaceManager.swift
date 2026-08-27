import Foundation
import HarnessKit
import JudgeKit
import ProjectKit   // SafeFile — the shared confinement/safe-read primitives (F17)

/// A staged file's before-picture for the produced/changed diff (T7). `size` is always recorded (cheap
/// metadata, any size); `bytes` are held only up to `WorkspaceManager.stagedSnapshotCap`, so a hostile
/// huge staged file can't exhaust memory. `bytes == nil` marks an over-cap file — `unchanged` then can't
/// prove byte-equality and fails safe: the file is reported as changed, never a silently-skipped input.
public struct StagedSnapshot: Sendable, Equatable {
    public let size: Int
    public let bytes: Data?
    public init(size: Int, bytes: Data?) { self.size = size; self.bytes = bytes }
}

/// Creates and tears down the per-trial sandbox a run executes in, and lists its post-run contents as
/// ground truth for the judge. Staging copies the skill (`SKILL.md` + `references/` + `scripts/` +
/// `assets/` and any other top-level entries) into the harness discovery path
/// `<workspace>/.claude/skills/<name>/`, **excluding `evaluations/`** — the model under test must never
/// see the expected answers or the grading it's judged against (constitution VI). Eval input `files`
/// are staged at the workspace root.
public struct WorkspaceManager: Sendable {
    /// Top-level skill entry never staged into a run workspace: the eval suite itself (the answers the
    /// model must never see). Hidden entries (`.skillet`/`.git`/`.env`/…) are excluded separately. The
    /// value — and the symlink/hidden predicates below — come from ``SkillBundleRules`` so the stager
    /// and doctor's `SkillBundleAudit` can't drift (Specs/008 §3).
    static let excludedFromSkill = SkillBundleRules.excludedFromSkill

    public init() {}

    /// A resolved eval fixture: where to copy it **from** (inside the skill) and where to stage it
    /// **to** under the workspace root. The two differ for the `fixtures/` fallback — a file physically
    /// at `evaluations/fixtures/foo` is staged as `fixtures/foo`, so a prompt that says `fixtures/foo`
    /// still resolves.
    public struct ResolvedFixture: Equatable, Sendable {
        public let source: URL
        public let sandboxRelativePath: String
    }

    /// Resolve an eval `files[]` entry to a ``ResolvedFixture``, or `nil` if rejected. The model may
    /// only ever see eval *inputs*, never the eval's own answers/records (constitution VI), so:
    ///   - absolute, empty, `..` traversal, symlink, and **hidden** path components are refused;
    ///   - under `evaluations/`, **only `evaluations/fixtures/**` is model-visible** — `evals.json`, the
    ///     run-record family, `sessions/`, `findings/`, and any other `evaluations/**` are private;
    ///   - `fixtures/…` resolves under the skill root, falling back to `evaluations/fixtures/…` (the
    ///     existing corpus layout), staged either way as `fixtures/…`;
    ///   - any other in-skill path is allowed once it clears the traversal/symlink/hidden guards.
    /// Shared by staging and RunCommand's pre-spend check.
    public static func resolveFixture(_ entry: String, skillDir: URL) -> ResolvedFixture? {
        guard !entry.isEmpty, !entry.hasPrefix("/") else { return nil }
        let parts = entry.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // No traversal, no hidden component anywhere in the declared path.
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0.hasPrefix(".") }) else { return nil }

        let base = skillDir.standardizedFileURL
        let source: URL
        if parts[0] == "evaluations" {
            // Only evaluations/fixtures/** is model-visible; the rest of evaluations/ is the harness's.
            guard parts.count >= 2, parts[1] == "fixtures" else { return nil }
            source = base.appendingPathComponent(entry).standardizedFileURL
        } else if parts[0] == "fixtures" {
            // Preferred public path; fall back to the corpus-compatible evaluations/fixtures/ location.
            let direct = base.appendingPathComponent(entry).standardizedFileURL
            source = FileManager.default.fileExists(atPath: direct.path)
                ? direct
                : base.appendingPathComponent("evaluations").appendingPathComponent(entry).standardizedFileURL
        } else {
            source = base.appendingPathComponent(entry).standardizedFileURL
        }

        // Confinement + no symlink anywhere in the source chain or nested inside it.
        guard source.path == base.path || source.path.hasPrefix(base.path + "/"),
              noSymlink(at: source, under: base) else { return nil }
        // **An ordinary file or a folder, and nothing else.** A named input that is a pipe, a socket or a
        // device is not something to hand a model, and what happens if you try depends on which
        // implementation of the file routines the machine has: measured on this one, copying a pipe fails
        // straight away with "operation not supported" — a message that explains nothing — and the
        // behaviour is not guaranteed to be that elsewhere. The check that removes the guesswork already
        // exists and is used by three other readers here, each citing the same rule about opening a file
        // whose kind you have not established.
        //
        // **Absence is still allowed through.** This decides whether a path is *permitted*, not whether it
        // is there — a missing input is the caller's to report, and requiring existence here broke three
        // cases that legitimately resolve a path before anything has been written. So the rule is only
        // about what is found if something is: a folder or an ordinary file passes, anything else does not.
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir) {
            guard isDir.boolValue || SafeFile.isRegularFile(source) else { return nil }
        }
        return ResolvedFixture(source: source, sandboxRelativePath: entry)
    }

    // These confinement predicates now live in ProjectKit's ``SafeFile`` (F17, shared with ScoreKit);
    // the wrappers below keep RunKit's existing call sites (and `RunnerTests`) unchanged.

    /// True iff no component from `base` down to `url` is a symlink, and `url` nests none.
    static func noSymlink(at url: URL, under base: URL) -> Bool { SafeFile.noSymlink(at: url, under: base) }

    /// Whether `url` is itself a symbolic link (lstat semantics — does not follow the link).
    public static func isSymlink(_ url: URL) -> Bool { SafeFile.isSymlink(url) }

    /// The first symlink at or under `url` (recursively), or `nil` if the subtree is symlink-free.
    /// Used to reject symlinks in staged skill-bundle entries and directory fixtures (F7 policy).
    public static func firstSymlink(in url: URL) -> URL? { SafeFile.firstSymlink(in: url) }

    /// The first symlink among the path components from `base` (exclusive) down to `target` (inclusive),
    /// or `nil` if every component is a real entry. Confines the skill / `evaluations/` I/O paths so a
    /// symlinked component can't redirect reads or writes outside the project.
    public static func firstSymlinkOnPath(from base: URL, to target: URL) -> URL? {
        SafeFile.firstSymlinkOnPath(from: base, to: target)
    }

    /// Top-level skill entries that staging copies: not `evaluations/`, not hidden. Shared by staging
    /// and RunCommand's pre-spend symlink check.
    public static func stagedEntries(skillDir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: skillDir.path)) ?? [])
            .filter { !excludedFromSkill.contains($0) && !SkillBundleRules.isHidden($0) }
    }

    /// Recursively copy `src` → `dst`, **skipping any symlink and any hidden entry at any depth** — so
    /// nested `.git`/`.env`/`.skillet` (and symlinks) under a staged bundle dir or directory fixture
    /// never reach the model's workspace (the top-level filter alone misses these).
    static func copyFiltered(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if isSymlink(src) { return }
        var isDir: ObjCBool = false
        fm.fileExists(atPath: src.path, isDirectory: &isDir)
        if isDir.boolValue {
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            for child in (try? fm.contentsOfDirectory(atPath: src.path)) ?? [] where !SkillBundleRules.isHidden(child) {
                try copyFiltered(from: src.appendingPathComponent(child), to: dst.appendingPathComponent(child))
            }
        } else {
            // Checked here as well as where a named input is resolved, because this walks *into* folders
            // and so meets files nobody named. Skipped the same way a link is, rather than refused: this
            // is staging a folder's contents, and one odd entry inside it is not a reason to abandon a
            // run. A file the caller named explicitly is a different matter and is refused there.
            guard SafeFile.isRegularFile(src) else { return }
            try fm.copyItem(at: src, to: dst)
        }
    }

    /// Create a fresh sandbox `base/<label>`, stage the skill (minus `evaluations/`) + input files.
    /// `stageSkill: false` (F15's baseline arm, `SkillSet.none`) stages **fixtures only** — the
    /// sandbox carries no skill at all; fixtures still resolve against the skill directory.
    /// (`FileManager` is non-`Sendable`, so this seam uses `.default` inline rather than storing it.)
    public func prepare(skill: SkillRef, files: [String], base: URL, label: String, stageSkill: Bool = true) throws -> Workspace {
        let fm = FileManager.default
        let root = base.appendingPathComponent(label, isDirectory: true)
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }   // no leaked state
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let source = URL(fileURLWithPath: skill.path, isDirectory: true)
        if stageSkill {
            // Stage the skill under the discovery path, minus evaluations/.
            let dest = root.appendingPathComponent(".claude/skills/\(skill.name)", isDirectory: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            // Stage non-hidden, non-evaluations top-level entries via the filtered copy, so nested hidden
            // files / symlinks are dropped too (RunCommand preflight also fails loud on a bundle symlink).
            for entry in Self.stagedEntries(skillDir: source) {
                try Self.copyFiltered(from: source.appendingPathComponent(entry), to: dest.appendingPathComponent(entry))
            }
        }

        // Stage eval input files at their declared sandbox path (the `fixtures/` fallback resolves the
        // physical source under evaluations/fixtures/). A missing file is skipped here; RunCommand
        // preflights existence before spending, so a typo fails loud rather than silently.
        for file in files {
            guard let fixture = Self.resolveFixture(file, skillDir: source),
                  fm.fileExists(atPath: fixture.source.path) else { continue }
            let fileDest = root.appendingPathComponent(fixture.sandboxRelativePath)
            try fm.createDirectory(at: fileDest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.copyFiltered(from: fixture.source, to: fileDest)
        }
        return Workspace(root: root)
    }

    /// Repo-relative paths of regular files present after the run — the judge's ground truth. Excludes
    /// the injected `.claude/` infrastructure (the staged skill is not something the run "produced").
    /// Paths come back already relative to the workspace, so nothing has to be trimmed or canonicalised.
    /// **What was cut is reported, and the files the run produced are never the ones cut.**
    ///
    /// The grader is told this list answers whether a file exists. It stops after a fixed number of
    /// entries, and until now said nothing when it did — so a run that installed dependencies or built
    /// something could push the file it actually made off the end, and a check like "the run created
    /// report.md" would be marked failed with the file sitting right there. That records a limitation of
    /// this tool as a fault in the skill being measured, which is the one thing a measuring tool must
    /// never do.
    ///
    /// Two changes. `keeping` names the files the run produced, and those are kept whatever else is
    /// dropped, so the realistic case is correct by construction rather than by the grader being careful.
    /// And when anything was still dropped it is said so, which is what lets the grader stop treating a
    /// gap in the list as proof of absence.
    /// `cap` is a parameter rather than a constant so the cut can be exercised by a test with a handful
    /// of files instead of the fifty thousand the shipped limit would need — an untested limit is one
    /// nobody knows the behaviour of.
    public func listing(_ workspace: Workspace, keeping produced: [String] = [],
                        cap: Int = WorkspaceManager.producedEntryCap) -> (files: [String], truncated: Bool) {
        let fm = FileManager.default
        let root = workspace.root
        let walked = Self.walk(root, cap: cap)
        let files = walked.entries.filter { rel in
            if rel == ".claude" || rel.hasPrefix(".claude/") { return false }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: root.appendingPathComponent(rel).path, isDirectory: &isDir)
            return !isDir.boolValue
        }
        // The produced files go in whether or not the walk reached them — they are what the checks are
        // about, and they are already bounded by the same limit, so adding them cannot run away.
        return (Array(Set(files).union(produced)).sorted(), walked.truncated)
    }

    // MARK: - Trigger-axis staging (F14)

    /// A prepared trigger sandbox: the workspace plus which corpus skills staged as stubs and which
    /// were skipped (missing/symlinked/fence-less `SKILL.md`) — skipped siblings are forensics, not
    /// failures; a skipped *target* is the caller's error to surface.
    public struct TriggerStaging: Sendable {
        public let workspace: Workspace
        public let staged: [String]
        public let skipped: [String]
    }

    /// The frontmatter-only stub for a visible-but-not-loaded skill (design §9.2 "bodies withheld";
    /// F14 D-2): the `---` fence **verbatim** (real name + description — the selection signal) with
    /// the body replaced by a marker. Textual extraction, deliberately not a YAML parse: RunKit must
    /// stay free of the `.Cxx` `ConfigYAML` target (interop containment, design §11).
    public static func frontmatterStub(markdown: String) -> String? {
        // Normalize CRLF first: in Swift, "\r\n" is ONE grapheme cluster, so splitting on "\n" never
        // fires on CRLF text at all — the YAML-level frontmatter parser tolerates CRLF, so this must
        // too, or a lint-clean skill silently fails to stage (review round 1, finding 3). The staged
        // stub is skillet-authored, so emitting it LF-normalized is fine.
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }
        guard let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else { return nil }
        let fence = lines[...close].joined(separator: "\n")
        return fence + "\n\n(stub — body withheld: skillet trigger-axis trial)\n"
    }

    /// Create a trigger-trial sandbox: every corpus skill staged as a **frontmatter stub** under the
    /// discovery path (`.only(load: [], visible: corpus)` — §9.3's whole-corpus selection menu, D-3).
    /// No eval fixtures: a trigger case is a bare query. Unstageable siblings are skipped and named.
    /// `skillsRoot` is the folder every candidate skill lives under, and it is the point every path is
    /// proved clean *from*. Without it, the read below could only refuse a shortcut — a file entry that
    /// silently points somewhere else — at the very last step of the path, so a shortcut planted on any
    /// folder along the way was followed and whatever it pointed at was staged and shown to the model.
    /// That gap has a name, `CWE-59` ("link following"), and the fix it prescribes is to prove every step,
    /// which needs a folder to start proving from — hence this argument.
    public func prepareTrigger(corpus: [SkillRef], skillsRoot: URL, base: URL, label: String) throws -> TriggerStaging {
        let fm = FileManager.default
        let root = base.appendingPathComponent(label, isDirectory: true)
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }   // no leaked state
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        var staged: [String] = []
        var skipped: [String] = []
        for skill in corpus {
            let skillDir = URL(fileURLWithPath: skill.path, isDirectory: true)
            let source = skillDir.appendingPathComponent("SKILL.md")
            // A symlinked skill FOLDER is refused like a symlinked file (review round 4, finding 3):
            // discovery doesn't filter symlinked directories, and following one would stage
            // out-of-repo content as a visible stub — the confinement rule is "never follow
            // symlinks when staging", at every level.
            guard !SkillBundleRules.isSymlink(skillDir),
                  !SkillBundleRules.isSymlink(source),
                  // Safe read (round 11): this runs PER TRIAL, after the once-per-run preflight — a
                  // SKILL.md swapped for a FIFO in that window hung the old unguarded
                  // `String(contentsOf:)` mid-run (the TOCTOU variant of the F33 hang class). A
                  // refusal skips the stub exactly like a missing frontmatter fence.
                  //
                  // **Every step of the path is proved, not just the last one.** The two checks above
                  // cover the skill's own folder and the file; the reader used here covers everything
                  // between the skills folder and them, which is the part a once-per-run check cannot
                  // keep true — this runs again on every attempt, and a folder can be swapped in between.
                  case let .success(markdown) = SafeFile.readConfinedRegularText(source, base: skillsRoot, cap: 1 << 20),
                  let stub = Self.frontmatterStub(markdown: markdown) else {
                skipped.append(skill.name)
                continue
            }
            let dest = root.appendingPathComponent(".claude/skills/\(skill.name)", isDirectory: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try stub.write(to: dest.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            staged.append(skill.name)
        }
        return TriggerStaging(workspace: Workspace(root: root), staged: staged.sorted(), skipped: skipped.sorted())
    }

    /// Remove the sandbox (the `.skillet/runs` cache is deletable; nothing here is authoritative, P2).
    public func destroy(_ workspace: Workspace) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: workspace.root.path) {
            try fm.removeItem(at: workspace.root)
        }
    }

    // MARK: - Grounded-judge content capture (F16)

    /// Raw bytes of the files staged into the workspace before the run — the baseline for the
    /// Bytes past this are not held in the staged before-picture (T7). Generous for real input fixtures
    /// (text/config/sample docs); its only job is to stop a hostile staged file from exhausting memory.
    static let stagedSnapshotCap = 16 << 20   // 16 MiB

    /// produced/changed snapshot diff (plan D-6). Non-`.claude`, non-symlink regular files only
    /// (staged input fixtures; the skill lives under `.claude/` and is never graded as output). The read
    /// is **bounded** (T7): hold bytes up to `stagedSnapshotCap`, always keep the true size, and record no
    /// bytes for an over-cap file so the post-run comparison fails safe (see `StagedSnapshot`/`unchanged`).
    public func snapshotStaged(_ workspace: Workspace) -> [String: StagedSnapshot] {
        var out: [String: StagedSnapshot] = [:]
        for rel in producedWalk(workspace) {
            let url = workspace.root.appendingPathComponent(rel)
            // Regular files only — never open a FIFO/socket (would block), never follow a symlink.
            guard Self.noSymlink(at: url, under: workspace.root), fileType(url) == .typeRegular,
                  let (data, fullSize) = boundedRead(url, cap: Self.stagedSnapshotCap) else { continue }
            out[rel] = StagedSnapshot(size: fullSize, bytes: fullSize <= Self.stagedSnapshotCap ? data : nil)
        }
        return out
    }

    /// The produced/changed files' **bounded, disclosed** contents (plan D-6/D-7, F16): created +
    /// modified vs `baseline` get their contents (cut at `perFileCap`, whole set bounded by `totalCap`),
    /// deleted staged files are disclosed with no content, genuinely-untouched inputs are skipped, and
    /// **symlinks are never followed** — a symlinked (or under-a-symlink) output is disclosed, never
    /// read, so a `out.txt → /etc/passwd` can't funnel host contents into the judge (plan-review P1).
    /// Deterministic (path-sorted) for byte-reproducible `--replay` re-grades. Reads are size-bounded
    /// (a huge output is not slurped whole).
    public func readProducedContents(_ workspace: Workspace, baseline: [String: StagedSnapshot], perFileCap: Int, totalCap: Int) -> [FileContent] {
        let fm = FileManager.default
        let root = workspace.root
        var results: [FileContent] = []
        var total = 0

        for rel in producedWalk(workspace) {
            let url = root.appendingPathComponent(rel)
            let staged = baseline[rel]
            let change: FileContent.Change = (staged == nil) ? .created : .modified
            // The entry itself is a symlink: never follow — disclose it (plan-review P1).
            if Self.isSymlink(url) {
                results.append(FileContent(path: rel, change: change, content: nil, symlink: true))
                continue
            }
            // A path UNDER a symlinked ancestor (e.g. `linkdir/inner.txt` where `linkdir` is a link):
            // the ancestor link is disclosed on its own row, so skip the phantom child — it isn't a real
            // produced file, and following it would read outside the sandbox. `noSymlink` also rejects a
            // symlink nested inside the entry, so this is the full confinement guard.
            if !Self.noSymlink(at: url, under: root) { continue }
            // Non-regular special file (FIFO / socket / device): disclose WITHOUT opening it — a
            // `FileHandle` read on a pipe blocks forever, which would hang capture past the harness
            // timeout (finding 1). This check is BEFORE any read, so `unchanged`/`boundedRead` never
            // touch a special file either.
            guard fileType(url) == .typeRegular else {
                results.append(FileContent(path: rel, change: change, content: nil, sizeBytes: fileSize(url), special: true))
                continue
            }
            // Hard link (link count > 1): another directory entry points at this inode — possibly a
            // host file outside the sandbox (a same-fs hard link; cross-fs hard links are impossible,
            // so this catches the realistic escape). Never read it — disclose. Defense-in-depth beside
            // the symlink guard; the robust fix is workspace-level isolation (a future sandbox pass).
            if linkCount(url) > 1 {
                results.append(FileContent(path: rel, change: change, content: nil, sizeBytes: fileSize(url), hardlink: true))
                continue
            }
            // A regular staged file whose bytes are unchanged is an input, not the skill's output.
            if let staged, unchanged(url, staged: staged) { continue }
            let allowed = min(perFileCap, max(0, totalCap - total))
            if allowed == 0 {   // total budget spent → disclose as omitted (no prefix shown; not truncation)
                results.append(FileContent(path: rel, change: change, content: nil, sizeBytes: fileSize(url), omitted: true))
                continue
            }
            guard let (data, fullSize) = boundedRead(url, cap: allowed) else {
                // A regular file that couldn't be opened (e.g. `chmod 000`): disclose it, never drop it
                // silently — the "every omission disclosed" rule (post-ship review finding).
                results.append(FileContent(path: rel, change: change, content: nil, sizeBytes: fileSize(url), unreadable: true))
                continue
            }
            let truncated = fullSize > data.count
            guard let text = Self.decodeText(data, truncated: truncated) else {
                // NUL or non-UTF-8 (after trimming an incomplete trailing scalar): withhold as binary,
                // disclosed with size — never lossy-decode into U+FFFD garbage (findings 2, 3).
                results.append(FileContent(path: rel, change: change, content: nil, sizeBytes: fullSize, binary: true))
                continue
            }
            let shown = text.utf8.count
            total += shown
            results.append(FileContent(path: rel, change: change, content: text, truncatedBytes: fullSize - shown, sizeBytes: fullSize))
        }
        // Deleted: a staged path with NO entry present now — using **lstat** existence, so a dangling
        // symlink that replaced a staged file (already disclosed above) is not *also* recorded as
        // deleted (finding 4).
        for rel in baseline.keys.sorted() {
            let url = root.appendingPathComponent(rel)
            if !Self.isSymlink(url) && !fm.fileExists(atPath: url.path) {
                results.append(FileContent(path: rel, change: .deleted, content: nil))
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    /// The file's type from its metadata attributes. Callers apply this only **after** the `isSymlink`
    /// / `noSymlink` guards, so the entry is never a symlink here (follow-vs-`lstat` semantics are moot);
    /// `nil` on error. A FIFO/device shows as `.typeUnknown`, a socket as `.typeSocket` — anything but
    /// `.typeRegular` must not be opened.
    private func fileType(_ url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType
    }

    /// The file's byte size from metadata (no read), for disclosing a withheld file's size.
    private func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int) ?? 0
    }

    /// The file's hard-link count (`st_nlink`) from metadata; `1` on error. `> 1` ⇒ the inode has
    /// another directory entry (possibly a host file), so the content is withheld, not read.
    private func linkCount(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.referenceCount]) as? Int) ?? 1
    }

    /// Strictly decode captured bytes as UTF-8, or `nil` to withhold as binary: **never** lossy-decode.
    /// A NUL byte ⇒ binary (git heuristic). When the read was truncated at the cap, at most **one**
    /// incomplete trailing UTF-8 scalar is trimmed before validation — a cap can only split the final
    /// character — so a valid text file cut mid-character stays text (minus the partial byte(s)), while
    /// genuinely non-text bytes still fail → binary.
    ///
    /// The trailing scalar is at most 4 bytes: a lead byte in `0xC2...0xF4` plus ≤ 3 continuation bytes
    /// (`10xxxxxx`). Crucially, an invalid byte like `0xFF`/`0xFE` or a run of > 3 continuation bytes is
    /// **not** a truncation artifact, so it is left in place and the decode falls through to `nil` ⇒
    /// binary (post-ship review: `0xFF` at the cap boundary must stay binary, not be stripped to text).
    ///
    /// Known heuristic limitation (accepted): with an absurdly small cap (< one scalar, ~4 bytes), a
    /// prefix of only stray continuation bytes can trim to empty and read as empty text. Unreachable at
    /// the shipped 32 KiB cap — a genuinely binary file's first 32 KiB carries a NUL or a
    /// non-continuation invalid byte and fails to binary.
    static func decodeText(_ data: Data, truncated: Bool) -> String? { SafeFile.decodeText(data, truncated: truncated) }

    /// The most entries one attempt's folder is walked for. A model given a folder to work in can create
    /// as many files as it likes, and listing them builds the whole list in memory before anything is
    /// filtered — so a runaway one could exhaust memory during the very step meant to record what it did.
    /// Every individual file was already bounded; the *number* of them was not. Far above any real run:
    /// a skill producing more than this has gone wrong in a way worth stopping on rather than recording.
    public static let producedEntryCap = 50_000

    /// **One walk, used by everything that lists a finished workspace.** There were two, written
    /// separately, and they drifted: one counted its entries and stopped, the other read the whole folder
    /// into memory in a single call and never looked at the limit — while its own description said it did.
    /// The one without the limit was the one the grading path actually used, so a run that produced tens
    /// of thousands of files could exhaust memory during the step meant to record what it produced.
    ///
    /// **Shortcuts are listed, never walked into.** A shortcut is a file entry that silently points
    /// somewhere else; the tree on the other side belongs to somebody else, and descending into one means
    /// walking whatever is there. Confirmed by the test that a shortcut to a folder is reported and its
    /// contents are not.
    ///
    /// Reports whether it stopped early, so a caller can say so rather than presenting a short list as a
    /// complete one.
    static func walk(_ root: URL, cap: Int) -> (entries: [String], truncated: Bool) {
        var entries: [String] = []
        // **A directory that cannot be read is not an empty one.** Answering "no entries, and that is the
        // complete list" tells the grader authoritatively that nothing exists, so every check of the form
        // "the run created X" fails — a fault in this tool recorded as a fault in the skill. Saying the
        // list is incomplete is the honest answer and is what stops absence being read as proof.
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return ([], true) }
        while let next = walker.nextObject() as? String {
            if entries.count >= cap { return (entries, true) }
            entries.append(next)
        }
        return (entries, false)
    }

    /// Non-`.claude` file-or-symlink entries under the workspace (dirs excluded), sorted. Symlink
    /// entries are kept (to be disclosed, never read); real directories are skipped.
    ///
    /// **Bounded by count as well as by size.** Stops after ``producedEntryCap`` entries rather than
    /// building an unbounded list.
    ///
    /// **This one does not report what it dropped, and that is on purpose.** Its sibling above feeds the
    /// grader's answer to "does this file exist", where a silent gap can turn a limitation of this tool
    /// into a recorded fault in the skill; it says what it cut for that reason. This one feeds the
    /// captured contents, where a file that is missing is simply not offered as evidence and nothing
    /// concludes anything from its absence. The comment here used to claim the caller disclosed the cut —
    /// no caller did.
    private func producedWalk(_ workspace: Workspace) -> [String] {
        let fm = FileManager.default
        let root = workspace.root
        let all = Self.walk(workspace.root, cap: Self.producedEntryCap).entries
        return all.filter { rel in
            if rel == ".claude" || rel.hasPrefix(".claude/") { return false }
            let url = root.appendingPathComponent(rel)
            if Self.isSymlink(url) { return true }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            return !isDir.boolValue
        }.sorted()
    }

    /// True iff `url`'s current bytes equal the staged bytes — size first (cheap), then a bounded byte
    /// compare only when sizes match (bounded by the small staged input).
    private func unchanged(_ url: URL, staged: StagedSnapshot) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        if let size, size != staged.size { return false }        // size differs → changed
        guard let bytes = staged.bytes else { return false }     // over-cap staged file: can't prove equality → fail safe (changed)
        guard let (data, fullSize) = boundedRead(url, cap: bytes.count) else { return false }
        return fullSize == bytes.count && data == bytes
    }

    /// Read up to `cap` bytes (the capture ceiling) without slurping a huge file whole; also returns
    /// the file's full byte size (from metadata) so truncation can be disclosed precisely.
    private func boundedRead(_ url: URL, cap: Int) -> (data: Data, fullSize: Int)? { SafeFile.boundedRead(url, cap: cap) }
}
