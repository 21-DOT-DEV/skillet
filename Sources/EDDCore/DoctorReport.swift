/// The `--json` payload for `skillet doctor` (`skillet.doctor/1`): the $0 preflight as a flat list
/// of check rows. Additive within the major — later doctor features (F20 frontmatter rules, the F21
/// `--paid` canary, the deferred §6.1 checklist items) land as new rows and check ids, never a
/// schema bump. The status semantics are frozen: a `failure` row carries a `remedy` and fails the
/// command (exit 3); a `warning` row never fails (a warning that exits non-zero breaks every CI
/// consumer — the brew-doctor lesson) but may also carry a `remedy` (e.g. the auth row's
/// `claude auth login`). Row **presence is guaranteed**: every check that *runs* emits at least one
/// row per subject — so an absent check id means the check did not run, never that it passed
/// silently (decided review round 2; the rule every future check inherits).
public struct DoctorReport: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.doctor/1"

    /// The frozen check-id vocabulary (dotted ids group by area; additive-only).
    public enum Check {
        public static let config = "config"
        public static let harnessBinary = "harness.binary"
        public static let harnessVersion = "harness.version"
        public static let harnessAuth = "harness.auth"
        public static let skillVisibility = "skill.visibility"
        public static let skillLint = "skill.lint"
        /// The trigger-test file's health (added F14 review round 4 — additive): absent/usable pass,
        /// empty warns (the runner skips it), invalid/symlinked fails (the runner refuses it).
        public static let skillTriggerEvals = "skill.trigger-evals"
    }

    /// One check result. `subject` names what was examined (a skill, a harness, a skill×harness
    /// pair); `nil` means project-level.
    public struct Row: Encodable, Sendable, Equatable {
        public enum Status: String, Encodable, Sendable {
            case pass
            case warning
            case failure
        }

        public let check: String
        public let subject: String?
        public let status: Status
        public let message: String
        /// The exact fixing action — present on every `failure` row, optionally on `warning` rows
        /// (P6: what/why/fix).
        public let remedy: String?

        public init(check: String, subject: String? = nil, status: Status, message: String, remedy: String? = nil) {
            self.check = check
            self.subject = subject
            self.status = status
            self.message = message
            self.remedy = remedy
        }

        /// A passing check.
        public static func pass(check: String, subject: String? = nil, message: String) -> Row {
            Row(check: check, subject: subject, status: .pass, message: message)
        }

        /// A non-failing finding; `remedy` optional (e.g. the auth row's `claude auth login`).
        public static func warning(check: String, subject: String? = nil, message: String, remedy: String? = nil) -> Row {
            Row(check: check, subject: subject, status: .warning, message: message, remedy: remedy)
        }

        /// A failing check — the remedy is required *by construction*, so a producer cannot ship a
        /// failure without its fix (P6; the memberwise init stays for codec/golden use).
        public static func failure(check: String, subject: String? = nil, message: String, remedy: String) -> Row {
            Row(check: check, subject: subject, status: .failure, message: message, remedy: remedy)
        }
    }

    public let healthy: Bool
    public let rows: [Row]

    public init(rows: [Row]) {
        self.rows = rows
        self.healthy = !rows.contains { $0.status == .failure }
    }

    /// Doctor's frozen exit contract: warnings never fail; any failure row is an environment error.
    public var exitCode: ExitCode { healthy ? .success : .environment }
}
