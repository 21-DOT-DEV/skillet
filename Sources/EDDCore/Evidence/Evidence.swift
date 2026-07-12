import Foundation

/// Which fix-lever a piece of evidence points at (design §7.3).
public enum Lever: String, Codable, Sendable, Equatable, CaseIterable {
    case eval, benchmark, lint, reference, config
    case skillMd = "skill_md"
}

/// How a machine-mined `Finding` was surfaced (design §7.3).
public enum FindingSource: String, Codable, Sendable, Equatable, CaseIterable {
    case scorer, judge
    case codeFeedback = "code_feedback"
}

/// A `Finding`'s confidence tier (design §7.3).
public enum Confidence: String, Codable, Sendable, Equatable, CaseIterable {
    case high, medium, low
}

/// The fields **every** evidence record shares (design §7.3). `FrictionEvent` is exactly this header;
/// `Finding` adds its machine-mined fields — held as a composed group so the shared shape + validation
/// live in one place (D2). On the wire the record flattens the header into the top-level frontmatter;
/// snake_case ⇄ camelCase is the seam's `YAMLDecoder`/`YAMLEncoder` key strategy, so this stays clean.
public struct EvidenceHeader: Codable, Sendable, Equatable {
    public var id: String
    public var skill: String
    public var domain: String
    public var lever: Lever
    public var state: LifecycleState
    /// The human's rationale for the current human-set state; required + non-empty when `state ∈
    /// {held, watch, closed}` (validated in `validate`, D5).
    public var stateReason: String?
    public var rootCause: String?
    /// Linked session-bundle ids — plain strings, **not** existence-checked (that's I/O, F30/later).
    public var sessions: [String]
    /// Sourced from the linked sessions' meta; `"unknown"` sentinel allowed.
    public var skillVersion: String
    public var model: String
    /// Filled at `codified` (e.g. `evals.json#snippets-compile`).
    public var eval: String?

    public init(id: String, skill: String, domain: String, lever: Lever, state: LifecycleState,
                stateReason: String? = nil, rootCause: String? = nil, sessions: [String] = [],
                skillVersion: String = "unknown", model: String = "unknown", eval: String? = nil) {
        self.id = id; self.skill = skill; self.domain = domain; self.lever = lever; self.state = state
        self.stateReason = stateReason; self.rootCause = rootCause; self.sessions = sessions
        self.skillVersion = skillVersion; self.model = model; self.eval = eval
    }

    // Custom decode so an absent optional/sentinel field takes its default rather than throwing
    // `keyNotFound` — `sessions` → `[]`, `skill_version`/`model` → `"unknown"`. Required fields
    // (`id`/`skill`/`domain`/`lever`/`state`) still throw when missing, surfaced as `missingField`.
    // The case order is **load-bearing**: synthesized `encode` emits in this order, which must match
    // the design §7.3 example — id, skill, domain, lever, state, state_reason, root_cause, sessions,
    // skill_version, model, eval (F29 review; asserted by `encodedFrictionKeyOrderMatchesTheDesignExample`).
    enum CodingKeys: String, CodingKey {
        case id, skill, domain, lever, state, stateReason, rootCause, sessions, skillVersion, model, eval
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        skill = try c.decode(String.self, forKey: .skill)
        domain = try c.decode(String.self, forKey: .domain)
        lever = try c.decode(Lever.self, forKey: .lever)
        state = try c.decode(LifecycleState.self, forKey: .state)
        stateReason = try c.decodeIfPresent(String.self, forKey: .stateReason)
        rootCause = try c.decodeIfPresent(String.self, forKey: .rootCause)
        sessions = try c.decodeIfPresent([String].self, forKey: .sessions) ?? []
        skillVersion = try c.decodeIfPresent(String.self, forKey: .skillVersion) ?? "unknown"
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "unknown"
        eval = try c.decodeIfPresent(String.self, forKey: .eval)
    }
}

/// The shared read-interface both records expose, so the later gates engine consumes friction + finding
/// uniformly (D2). `schema` is the self-describing format tag the reader dispatches on.
public protocol Evidence: Codable, Sendable, Equatable {
    static var schema: String { get }
    var header: EvidenceHeader { get }
}

public extension Evidence {
    /// The **semantic** checks `Codable` decode can't express (types / enums / required-field presence
    /// already came free from decode): the `id` shape, the `state_reason` conditional (D5), and — when
    /// reading from a file — the `id` ↔ filename-stem cross-check (F4). `filename` is `nil` for
    /// standalone-text decode (tests, non-file sources), which skips the stem check.
    func validate(filename: String? = nil) throws {
        guard EvidenceValidation.isValidID(header.id) else {
            throw EvidenceError.invalidValue(field: "id", value: header.id)
        }
        if let filename {
            let stem = filename.hasSuffix(".md") ? String(filename.dropLast(3)) : filename
            guard stem == header.id else {
                throw EvidenceError.idMismatch(id: header.id, filename: filename)
            }
        }
        if [.held, .watch, .closed].contains(header.state) {
            let reason = header.stateReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !reason.isEmpty else { throw EvidenceError.missingStateReason(state: header.state) }
        }
    }
}

enum EvidenceValidation {
    /// `<YYYY-MM-DD>-<kebab-slug>` — a 10-char ISO date, a dash, then a non-empty lowercase kebab slug.
    /// Scalar-based (not `Character`) so the ASCII bounds are unambiguous (mirrors the capture slug check).
    static func isValidID(_ id: String) -> Bool {
        let s = Array(id.unicodeScalars)
        guard s.count >= 12 else { return false }
        func digit(_ i: Int) -> Bool { s[i] >= "0" && s[i] <= "9" }
        guard digit(0), digit(1), digit(2), digit(3), s[4] == "-",
              digit(5), digit(6), s[7] == "-", digit(8), digit(9), s[10] == "-" else { return false }
        func isSlugChar(_ c: Unicode.Scalar) -> Bool { (c >= "a" && c <= "z") || (c >= "0" && c <= "9") }
        let slug = s[11...]
        guard let first = slug.first, isSlugChar(first) else { return false }
        return slug.dropFirst().allSatisfy { isSlugChar($0) || $0 == "-" }
    }
}
