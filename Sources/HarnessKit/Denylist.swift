/// The harness version ban policy (§9.1) — data with provenance, not a version floor. The anti-footgun
/// rule: an explicitly pinned banned binary is a hard error; an auto-discovered one warns and falls back.
public struct Denylist: Sendable, Equatable {
    public var bannedVersions: Set<String>
    public init(bannedVersions: Set<String>) { self.bannedVersions = bannedVersions }

    /// Shipped seed: claude-code `2.1.143` — a Skill-tool regression that returned `is_error` on every
    /// invocation (cost three eval sessions misdiagnosed as "prose insufficient" before bisection).
    public static let claudeCodeSeed = Denylist(bannedVersions: ["2.1.143"])

    public enum Decision: Sendable, Equatable {
        case allowed
        /// Explicitly pinned + banned → hard error (exit 3); never a silent swap.
        case refused(version: String)
        /// Auto-discovered + banned → loud warning, fall back to a non-banned binary.
        case warnedFallback(version: String)
    }

    /// Classify a resolved binary's version. `pinned` = explicitly pinned (flag/env/config);
    /// `bypassed` = the audited `SKILLET_ALLOW_BANNED_<ID>` escape hatch.
    public func check(version: String, pinned: Bool, bypassed: Bool) -> Decision {
        guard bannedVersions.contains(version), !bypassed else { return .allowed }
        return pinned ? .refused(version: version) : .warnedFallback(version: version)
    }
}
