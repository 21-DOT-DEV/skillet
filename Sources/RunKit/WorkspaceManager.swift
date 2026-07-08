import Foundation
import HarnessKit

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
        return ResolvedFixture(source: source, sandboxRelativePath: entry)
    }

    /// True iff no component from `base` down to `url` is a symlink, and `url` nests none.
    static func noSymlink(at url: URL, under base: URL) -> Bool {
        var walk = base
        for component in url.path.dropFirst(base.path.count).split(separator: "/") {
            walk.appendPathComponent(String(component))
            if isSymlink(walk) { return false }
        }
        return firstSymlink(in: url) == nil
    }

    /// Whether `url` is itself a symbolic link (lstat semantics — does not follow the link).
    /// Delegates to the shared ``SkillBundleRules`` (kept here so existing call sites don't churn).
    public static func isSymlink(_ url: URL) -> Bool {
        SkillBundleRules.isSymlink(url)
    }

    /// The first symlink at or under `url` (recursively), or `nil` if the subtree is symlink-free.
    /// Used to reject symlinks in staged skill-bundle entries and directory fixtures (F7 policy).
    public static func firstSymlink(in url: URL) -> URL? {
        if isSymlink(url) { return url }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return nil }
        for case let child as URL in enumerator where isSymlink(child) { return child }
        return nil
    }

    /// The first symlink among the path components from `base` (exclusive) down to `target` (inclusive),
    /// or `nil` if every component is a real entry. Confines the skill / `evaluations/` I/O paths so a
    /// symlinked component can't redirect reads or writes outside the project — the staging check skips
    /// `evaluations/` and the skill root itself, so those need this guard.
    public static func firstSymlinkOnPath(from base: URL, to target: URL) -> URL? {
        let basePath = base.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        guard targetPath == basePath || targetPath.hasPrefix(basePath + "/") else { return target }   // not under base → escape
        var walk = base.standardizedFileURL
        for component in targetPath.dropFirst(basePath.count).split(separator: "/") {
            walk.appendPathComponent(String(component))
            if isSymlink(walk) { return walk }
        }
        return nil
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
    /// Uses `subpathsOfDirectory` so paths are already root-relative (no symlink/prefix canonicalization).
    public func listing(_ workspace: Workspace) throws -> [String] {
        let fm = FileManager.default
        let root = workspace.root
        let all = (try? fm.subpathsOfDirectory(atPath: root.path)) ?? []
        return all.filter { rel in
            if rel == ".claude" || rel.hasPrefix(".claude/") { return false }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: root.appendingPathComponent(rel).path, isDirectory: &isDir)
            return !isDir.boolValue
        }.sorted()
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
    public func prepareTrigger(corpus: [SkillRef], base: URL, label: String) throws -> TriggerStaging {
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
                  let markdown = try? String(contentsOf: source, encoding: .utf8),
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
}
