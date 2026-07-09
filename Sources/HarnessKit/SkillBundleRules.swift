import Foundation
import ProjectKit

/// The staging-filter rules shared by the run stager (RunKit's `WorkspaceManager`) and the $0
/// preflight audit (`SkillBundleAudit`) — the single source of truth Specs/008 §3 calls for, so a
/// rule change cannot drift between "what stages" and "what doctor checks" without both moving.
/// Walk *structure* stays per-consumer (copy vs. report) and is guarded by `RunKitTests`'
/// `StagingParityTests`. The symlink/hidden predicates now live in ProjectKit's `SafeFile` (F17, so
/// ScoreKit can share them); these stay as thin delegates so existing callers don't churn.
public enum SkillBundleRules {
    /// The private eval namespace — never part of the model-visible bundle (constitution VI): the
    /// answers and records the model must never see. A *denylist* — not a fixed allowlist — because
    /// real skills carry varied bundle dirs beyond `references`/`scripts`/`assets` (e.g. `agents/`,
    /// `fixtures/`, `eval-viewer/`), and a narrow allowlist would silently drop them.
    public static let excludedFromSkill: Set<String> = ["evaluations"]

    /// Whether `url` is itself a symbolic link (lstat semantics — does not follow the link).
    /// Symlinks are dropped by staging at any depth (the escape/leak guard for a paid harness).
    public static func isSymlink(_ url: URL) -> Bool { SafeFile.isSymlink(url) }

    /// Whether a path component is hidden — dropped by staging at any depth (`.git`/`.env`/`.skillet`/…).
    public static func isHidden(_ name: String) -> Bool { SafeFile.isHidden(name) }
}
