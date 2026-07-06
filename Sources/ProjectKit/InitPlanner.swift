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
                // The design-promised skeletons (§6.1 `init` — "evals.json and trigger-eval.json
                // skeletons if absent"; closed in F14 review round 5: `run`'s remedies point users
                // here). Deliberately EMPTY: an empty axis file skips its axis with a note and shows
                // as a "no cases yet" doctor warning — an onboarding nudge that can never spend.
                file(evaluations.appendingPathComponent("evals.json"),
                     "{\"skill_name\":\(Self.jsonEscaped(skill.lastPathComponent)),\"evals\":[]}\n")
                file(evaluations.appendingPathComponent("trigger-eval.json"), "[]\n")
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

    /// JSON-encode a string value (quotes, backslashes, control characters escaped): a skill folder
    /// legally named `we"ird` must scaffold VALID JSON, never a corrupt frozen artifact (review
    /// round 6). Plain interpolation was an injection.
    static func jsonEscaped(_ value: String) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"skill\""
    }
}
