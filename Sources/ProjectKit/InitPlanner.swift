import Foundation

/// One filesystem change `init` intends to make.
public enum InitAction: Sendable, Equatable {
    case createDirectory(URL)
    case writeFile(URL, contents: String)

    public var url: URL {
        switch self {
        case let .createDirectory(url): url
        case let .writeFile(url, _): url
        }
    }
}

/// The idempotent plan for one `init`: only the **missing** targets become actions; targets that
/// already exist are recorded as `skipped`. Pure — computed from the probed filesystem state.
public struct InitPlan: Sendable, Equatable {
    public var actions: [InitAction]
    public var skipped: [URL]
    public var skills: [String]
}

/// Computes the `InitPlan` (design §6.1): repo-root `skillet.yaml`, the self-owned
/// `.skillet/.gitignore` cache ignore, and per-skill `evaluations/{friction,findings,sessions}/`
/// evidence directories — creating only what's absent.
public struct InitPlanner: Sendable {
    let probe: DirectoryProbe

    public init(probe: DirectoryProbe = FileSystemProbe()) {
        self.probe = probe
    }

    public func plan(root: URL, skillsRoot: String, skills: [URL]) -> InitPlan {
        var actions: [InitAction] = []
        var skipped: [URL] = []

        func has(_ url: URL) -> Bool {
            probe.exists(named: url.lastPathComponent, in: url.deletingLastPathComponent())
        }
        func file(_ url: URL, _ contents: String) {
            if has(url) { skipped.append(url) } else { actions.append(.writeFile(url, contents: contents)) }
        }
        func directory(_ url: URL) {
            if has(url) { skipped.append(url) } else { actions.append(.createDirectory(url)) }
        }

        // Repo-root config.
        file(root.appendingPathComponent("skillet.yaml"), SkilletConfigTemplate.contents(skillsRoot: skillsRoot))

        // Self-owned cache ignore (never touch the repo-root .gitignore).
        let cache = root.appendingPathComponent(".skillet")
        directory(cache)
        file(cache.appendingPathComponent(".gitignore"), "*\n")

        // Skills, or an empty skills root for a fresh repo.
        if skills.isEmpty {
            directory(root.appendingPathComponent(skillsRoot))
        } else {
            for skill in skills {
                let evaluations = skill.appendingPathComponent("evaluations")
                directory(evaluations)
                for sub in ["friction", "findings", "sessions"] {
                    let dir = evaluations.appendingPathComponent(sub)
                    directory(dir)
                    // Keep each otherwise-empty evidence directory tracked with a Git-recognized
                    // `.gitignore` (not a made-up `.gitkeep`) so it survives renames. It ignores
                    // nothing — evidence committed here is tracked normally (D3).
                    file(dir.appendingPathComponent(".gitignore"), "# Keep this evidence directory tracked even when empty.\n")
                }
            }
        }

        return InitPlan(actions: actions, skipped: skipped, skills: skills.map(\.lastPathComponent).sorted())
    }
}
