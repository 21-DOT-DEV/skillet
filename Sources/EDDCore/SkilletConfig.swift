/// The committed `skillet.yaml` configuration as a **pure** model (design §5.2). Decoded by the
/// isolated `ConfigYAML` target — this type carries no `swift-yaml`/C++-interop dependency, so the
/// rest of the core stays interop-free. F6 reads only the slice it needs (project + harness path);
/// F3 builds full precedence + `config list --origins` on top. Unmodeled keys are ignored on decode.
public struct SkilletConfig: Codable, Sendable, Equatable {
    public var project: Project?
    public var harness: Harness?
    public var lint: Lint?
    public var runs: Runs?
    public var judge: Judge?
    public var scorers: Scorers?

    public init(project: Project? = nil, harness: Harness? = nil, lint: Lint? = nil, runs: Runs? = nil, judge: Judge? = nil, scorers: Scorers? = nil) {
        self.project = project
        self.harness = harness
        self.lint = lint
        self.runs = runs
        self.judge = judge
        self.scorers = scorers
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

    /// The `runs:` knobs (design §5.2): trials per eval, the per-trial watchdog timeout, concurrency,
    /// and the spend-confirm threshold. Absent keys fall back to the shipped defaults. (The template's
    /// `infra_retries` is unmodeled here — ignored on decode — until F18 lands infra-retry.)
    public struct Runs: Codable, Sendable, Equatable {
        /// Trials per eval (overridable per invocation with `--runs`).
        public var k: Int
        /// Per-trial hard timeout, a duration string (e.g. `"10m"`).
        public var timeout: String
        /// Concurrent trials (Phase 1 ships serial: `1`).
        public var concurrency: Int
        /// `skillet run` confirms on the TTY when the estimated trial count exceeds this (design P9).
        public var confirmAboveTrials: Int
        /// Cap (bytes) on a single trial's captured stdout/stderr. Defaults to 64 MiB — big enough that a
        /// normal large `stream-json` session isn't truncated into a false failure, bounded so a runaway
        /// child can't exhaust memory. (Overflow beyond this stays a failed trial; true infra-class +
        /// retry is F18.)
        public var maxOutputBytes: Int

        public init(k: Int = 3, timeout: String = "10m", concurrency: Int = 1, confirmAboveTrials: Int = 25, maxOutputBytes: Int = 64 << 20) {
            self.k = k
            self.timeout = timeout
            self.concurrency = concurrency
            self.confirmAboveTrials = confirmAboveTrials
            self.maxOutputBytes = maxOutputBytes
        }

        enum CodingKeys: String, CodingKey {
            case k, timeout, concurrency
            case confirmAboveTrials = "confirm_above_trials"
            case maxOutputBytes = "max_output_bytes"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            k = try container.decodeIfPresent(Int.self, forKey: .k) ?? 3
            timeout = try container.decodeIfPresent(String.self, forKey: .timeout) ?? "10m"
            concurrency = try container.decodeIfPresent(Int.self, forKey: .concurrency) ?? 1
            confirmAboveTrials = try container.decodeIfPresent(Int.self, forKey: .confirmAboveTrials) ?? 25
            maxOutputBytes = try container.decodeIfPresent(Int.self, forKey: .maxOutputBytes) ?? (64 << 20)
        }
    }

    /// The `judge:` knobs (design §5.2): which adapter backs the judge and which model it targets.
    /// `provider` is an adapter id with the judging capability — Phase 1 default `claude-code` (the
    /// text judge shells the resolved `claude` CLI). `model` is **required-explicit** (design §14-4,
    /// decided 2026-07-01): there is deliberately no shipped fallback — a silently-defaulted judge is
    /// the cross-machine reproducibility hazard skillet refuses (the same eval config must never be
    /// graded by different models on different machines). `init` writes one; `run` errors when absent.
    public struct Judge: Codable, Sendable, Equatable {
        public var provider: String
        public var model: String?

        public init(provider: String = "claude-code", model: String? = nil) {
            self.provider = provider
            self.model = model
        }

        enum CodingKeys: String, CodingKey { case provider, model }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "claude-code"
            model = try container.decodeIfPresent(String.self, forKey: .model)
        }
    }

    /// The `scorers:` knobs (design §5.2), read by `skillet score` (F17). All lists default to `[]`, so a
    /// partial — or absent — block is valid. `vendored_prefixes` = folder names to skip (gitignore-style
    /// whole-segment, any depth). `vocab.exempt` = domain phrases removed from the slop word-list before
    /// scoring (whole-entry, case-insensitive). `disable` = default-on rule ids to turn off; `enable` =
    /// experimental/default-off rule ids (e.g. `SKILL-S006`) to turn on (`disable` wins over `enable`).
    /// Built-in defaults are all `[]`; `skillet init`'s template pre-writes suggested `vendored_prefixes`.
    public struct Scorers: Codable, Sendable, Equatable {
        public var vendoredPrefixes: [String]
        public var vocab: Vocab
        public var disable: [String]
        public var enable: [String]

        public init(vendoredPrefixes: [String] = [], vocab: Vocab = Vocab(), disable: [String] = [], enable: [String] = []) {
            self.vendoredPrefixes = vendoredPrefixes
            self.vocab = vocab
            self.disable = disable
            self.enable = enable
        }

        enum CodingKeys: String, CodingKey {
            case vendoredPrefixes = "vendored_prefixes"
            case vocab, disable, enable
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            vendoredPrefixes = try container.decodeIfPresent([String].self, forKey: .vendoredPrefixes) ?? []
            vocab = try container.decodeIfPresent(Vocab.self, forKey: .vocab) ?? Vocab()
            disable = try container.decodeIfPresent([String].self, forKey: .disable) ?? []
            enable = try container.decodeIfPresent([String].self, forKey: .enable) ?? []
        }

        public struct Vocab: Codable, Sendable, Equatable {
            public var exempt: [String]
            public init(exempt: [String] = []) { self.exempt = exempt }
            enum CodingKeys: String, CodingKey { case exempt }
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                exempt = try container.decodeIfPresent([String].self, forKey: .exempt) ?? []
            }
        }
    }
}
