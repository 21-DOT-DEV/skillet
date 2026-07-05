import Foundation

/// The $0 positive-load audit behind `doctor`'s skill-visibility check (design §9.2): would the
/// *whole* model-visible bundle survive the run stager's filter rules? Staging (RunKit's
/// `WorkspaceManager`) copies every non-hidden, non-`evaluations/` top-level entry and **silently
/// drops symlinks and hidden entries at any depth** — safe for the sandbox, but it means a symlinked
/// `references/` file yields a harness running with an incomplete bundle: the `--skill-path`
/// false-negative class (P6). The audit makes that drop loud *before* any paid run. The filter
/// *rules* are shared with the stager via ``SkillBundleRules`` (Specs/008 §3); walk-structure
/// parity is guarded by `RunKitTests` (`StagingParityTests`).
public enum SkillBundleAudit {
    public struct Result: Sendable, Equatable {
        /// `nil` when `SKILL.md` is a stageable regular file; else the human reason (missing/symlink).
        public let skillMDIssue: String?
        /// Bundle-relative paths staging would silently drop as symlinks — failures (incomplete bundle).
        public let symlinks: [String]
        /// Bundle-relative hidden entries staging drops by policy — warnings (`.DS_Store`-class noise,
        /// but a hidden file a reference *depends on* would vanish, so doctor shows them).
        public let droppedHidden: [String]

        /// The positive-load condition: `SKILL.md` stages and nothing is silently dropped as a symlink.
        public var isVisible: Bool { skillMDIssue == nil && symlinks.isEmpty }
    }

    /// Audit `skillDirectory` against the staging filter. Pure filesystem walk — no subprocess, $0.
    public static func audit(skillDirectory: URL) -> Result {
        let fm = FileManager.default
        let base = skillDirectory.standardizedFileURL

        let skillMD = base.appendingPathComponent("SKILL.md")
        let skillMDIssue: String?
        if SkillBundleRules.isSymlink(skillMD) {
            skillMDIssue = "SKILL.md is a symlink (staging and `run` refuse symlinked skill files)"
        } else if !fm.fileExists(atPath: skillMD.path) {
            skillMDIssue = "no SKILL.md at \(base.path)"
        } else {
            skillMDIssue = nil
        }

        var symlinks: [String] = []
        var hidden: [String] = []
        for entry in (try? fm.contentsOfDirectory(atPath: base.path))?.sorted() ?? [] {
            if SkillBundleRules.excludedFromSkill.contains(entry) { continue }      // private: not audited
            if SkillBundleRules.isHidden(entry) { hidden.append(entry); continue }  // never staged
            walk(base.appendingPathComponent(entry), relative: entry, symlinks: &symlinks, hidden: &hidden)
        }
        return Result(skillMDIssue: skillMDIssue, symlinks: symlinks.sorted(), droppedHidden: hidden.sorted())
    }

    /// Mirror the stager's `copyFiltered`: a symlink or hidden entry is dropped where found — record
    /// it and do not descend below it.
    private static func walk(_ url: URL, relative: String, symlinks: inout [String], hidden: inout [String]) {
        let fm = FileManager.default
        if SkillBundleRules.isSymlink(url) {
            symlinks.append(relative)
            return
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        for child in (try? fm.contentsOfDirectory(atPath: url.path))?.sorted() ?? [] {
            let childRelative = relative + "/" + child
            if SkillBundleRules.isHidden(child) {
                hidden.append(childRelative)
                continue
            }
            walk(url.appendingPathComponent(child), relative: childRelative, symlinks: &symlinks, hidden: &hidden)
        }
    }
}
