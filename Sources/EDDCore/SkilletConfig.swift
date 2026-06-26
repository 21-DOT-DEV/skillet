/// The committed `skillet.yaml` configuration as a **pure** model (design §5.2). Decoded by the
/// isolated `ConfigYAML` target — this type carries no `swift-yaml`/C++-interop dependency, so the
/// rest of the core stays interop-free. F6 reads only the slice it needs (project + harness path);
/// F3 builds full precedence + `config list --origins` on top. Unmodeled keys are ignored on decode.
public struct SkilletConfig: Codable, Sendable, Equatable {
    public var project: Project?
    public var harness: Harness?
    public var lint: Lint?

    public init(project: Project? = nil, harness: Harness? = nil, lint: Lint? = nil) {
        self.project = project
        self.harness = harness
        self.lint = lint
    }

    public struct Project: Codable, Sendable, Equatable {
        public var skillsRoot: String?
        public init(skillsRoot: String? = nil) { self.skillsRoot = skillsRoot }
        enum CodingKeys: String, CodingKey { case skillsRoot = "skills_root" }
    }

    /// The `harness:` mapping — modeled keys only (`default`, `matrix`, and the per-harness entries we
    /// read); other harness ids in the file are ignored on decode.
    public struct Harness: Codable, Sendable, Equatable {
        public var `default`: String?
        public var matrix: [String]?
        public var claudeCode: Entry?

        public init(default: String? = nil, matrix: [String]? = nil, claudeCode: Entry? = nil) {
            self.default = `default`
            self.matrix = matrix
            self.claudeCode = claudeCode
        }

        enum CodingKeys: String, CodingKey {
            case `default`, matrix
            case claudeCode = "claude-code"
        }

        public struct Entry: Codable, Sendable, Equatable {
            public var path: String?
            public init(path: String? = nil) { self.path = path }
        }
    }

    /// The `lint:` knobs (design §5.2): rule exemptions and the `SKILL-L003` body-line budgets.
    /// Absent keys fall back to the shipped defaults, so a partial — or entirely absent — `lint:`
    /// block is valid; the executable uses `Lint()` when the file has no `lint:` section.
    public struct Lint: Codable, Sendable, Equatable {
        /// Stable rule ids to suppress, e.g. `["SKILL-L011"]`.
        public var disable: [String]
        /// `SKILL-L003` warns above this many body lines (excluding frontmatter + fenced code).
        public var bodyWarnLines: Int
        /// `SKILL-L003` errors above this many body lines.
        public var bodyErrorLines: Int

        public init(disable: [String] = [], bodyWarnLines: Int = 500, bodyErrorLines: Int = 1000) {
            self.disable = disable
            self.bodyWarnLines = bodyWarnLines
            self.bodyErrorLines = bodyErrorLines
        }

        enum CodingKeys: String, CodingKey {
            case disable
            case bodyWarnLines = "body_warn_lines"
            case bodyErrorLines = "body_error_lines"
        }

        // Decode each knob independently so a partial `lint:` block (or none) fills the rest with the
        // shipped defaults rather than failing to decode.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            disable = try container.decodeIfPresent([String].self, forKey: .disable) ?? []
            bodyWarnLines = try container.decodeIfPresent(Int.self, forKey: .bodyWarnLines) ?? 500
            bodyErrorLines = try container.decodeIfPresent(Int.self, forKey: .bodyErrorLines) ?? 1000
        }
    }
}
