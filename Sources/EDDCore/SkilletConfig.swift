/// The committed `skillet.yaml` configuration as a **pure** model (design §5.2). Decoded by the
/// isolated `ConfigYAML` target — this type carries no `swift-yaml`/C++-interop dependency, so the
/// rest of the core stays interop-free. F6 reads only the slice it needs (project + harness path);
/// F3 builds full precedence + `config list --origins` on top. Unmodeled keys are ignored on decode.
public struct SkilletConfig: Codable, Sendable, Equatable {
    public var project: Project?
    public var harness: Harness?

    public init(project: Project? = nil, harness: Harness? = nil) {
        self.project = project
        self.harness = harness
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
}
