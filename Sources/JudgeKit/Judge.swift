import Foundation
import EDDCore
import TraceKit

/// What a ``Judge`` grades from — assembled by the runner after a trial completes. The judge sees the
/// run's final response, the normalized ``Trace`` (which skill fired, tools, per-turn files), and the
/// **ground-truth** post-run workspace listing. The listing is what makes a *claimed-but-not-created*
/// file judgeable: if the response says it wrote `report.md` and `report.md` is absent here, that is a
/// FAIL on existence, not on the model's say-so. File-*content* grounding (does the file say the right
/// thing) is the grounded judge, F16.
public struct JudgeEvidence: Sendable, Equatable {
    /// The run's final assistant response text.
    public let responseText: String
    /// The normalized execution trace.
    public let trace: Trace
    /// Repo-relative paths actually present in the workspace after the run — the ground truth.
    public let workspaceListing: [String]
    /// The **produced/changed** files' bounded contents (F16 grounded judge) — created + modified vs
    /// what the runner staged, deleted/skipped/cut all disclosed. `nil` on the text-judge path (never
    /// captured, no cost). The grounded judge grades against these; the text judge ignores them.
    public let fileContents: [FileContent]?

    public init(responseText: String, trace: Trace, workspaceListing: [String], fileContents: [FileContent]? = nil) {
        self.responseText = responseText
        self.trace = trace
        self.workspaceListing = workspaceListing
        self.fileContents = fileContents
    }
}

/// One produced/changed file's captured evidence (F16). `content` holds the (possibly cut) text; the
/// disclosure fields make any omission explicit so an absence can never be read as an empty/wrong
/// file — the load-bearing honesty rule (plan D-3).
public struct FileContent: Codable, Sendable, Equatable {
    public enum Change: String, Codable, Sendable, Equatable { case created, modified, deleted }
    public let path: String
    public let change: Change
    /// The captured text, cut to the per-file cap. `nil` for a `deleted`/`binary`/`special`/`symlink`
    /// entry. Never lossy — a non-UTF-8 file is withheld as `binary`, never mangled into U+FFFD text.
    public let content: String?
    /// Bytes not shown after the shown prefix (past the per-file cap, or an incomplete trailing scalar
    /// trimmed) — `> 0` **always** pairs with a non-nil `content` prefix. A file whose content is
    /// withheld entirely (`omitted`/`binary`/…) leaves this `0` and discloses its size via `sizeBytes`.
    public let truncatedBytes: Int
    /// The file's full byte size — so a withheld `binary`/`special` file discloses "N bytes", not just
    /// "withheld" (finding 3). `0` for a `deleted` entry.
    public let sizeBytes: Int
    /// Contents withheld because the bytes aren't UTF-8 text (`[binary, sizeBytes bytes]`).
    public let binary: Bool
    /// Contents withheld because the entry is a non-regular special file — a FIFO / socket / device
    /// that is **never opened** (opening one would block capture indefinitely; finding 1).
    public let special: Bool
    /// Contents withheld because the entry is a symlink — never followed (`[symlink → skipped]`, P1).
    public let symlink: Bool
    /// Contents withheld because the regular file could not be **opened** (e.g. `chmod 000`) — a
    /// disclosed omission, never a silent drop (so an unreadable file can't read as empty/wrong).
    public let unreadable: Bool
    /// Contents withheld because the file has **multiple hard links** (link count > 1) — another
    /// directory entry points at the same inode, possibly a host file outside the sandbox (a same-fs
    /// hard link), so it is never read (defense-in-depth alongside the symlink guard).
    public let hardlink: Bool
    /// Contents withheld because the **total evidence budget** was already spent before this file — none
    /// of its bytes are shown (distinct from a truncated prefix); `sizeBytes` discloses its size.
    public let omitted: Bool
    // NOTE (tracked cleanup): the six withheld-reason booleans below should consolidate into one
    // `enum Withheld { binary, special, symlink, unreadable, hardlink, omitted }?` in the next
    // substantive touch of this type — `content == nil` (non-deleted) would then ⟺ `withheld != nil`.

    public init(path: String, change: Change, content: String?, truncatedBytes: Int = 0, sizeBytes: Int = 0, binary: Bool = false, special: Bool = false, symlink: Bool = false, unreadable: Bool = false, hardlink: Bool = false, omitted: Bool = false) {
        self.path = path
        self.change = change
        self.content = content
        self.truncatedBytes = truncatedBytes
        self.sizeBytes = sizeBytes
        self.binary = binary
        self.special = special
        self.symlink = symlink
        self.unreadable = unreadable
        self.hardlink = hardlink
        self.omitted = omitted
    }
}

/// Whether the runner captures produced-file contents for the judge (F16). Set from the `--judge`
/// selection: the grounded judge needs contents; the text judge stays listing-only (no read, no cost).
public enum EvidencePolicy: Sendable, Equatable {
    case listingOnly
    case withContents(perFileCap: Int, totalCap: Int)

    /// The shipped grounded caps (plan D-7): 32 KiB per file, 128 KiB total — holds typical whole
    /// outputs while keeping the grading prompt in the range where judges stay reliable.
    public static let groundedDefault = EvidencePolicy.withContents(perFileCap: 32 * 1024, totalCap: 128 * 1024)
}

/// Grades one criterion (one `expected_behavior` line) against a trial's ``JudgeEvidence``, yielding a
/// ``Verdict``. Effectful (a real judge shells a model) — kept behind this protocol so the runner and
/// `pass^k` math stay deterministic and the judge is swappable (text now, grounded F16, replay F19).
public protocol Judge: Sendable {
    func verdict(for criterion: String, evidence: JudgeEvidence) async throws -> Verdict
}

/// The single "ask a model a one-shot prompt, get its text back" seam. Injected into ``TextJudge`` so
/// the prompt-building + verdict-parsing logic is unit-tested with a fake, and the real `claude`-CLI
/// runner (RunKit) is the only piece that touches a subprocess — mirroring HarnessKit's
/// `ProcessLauncher` discipline (constitution VI).
public protocol JudgeRunner: Sendable {
    func ask(prompt: String, model: String) async throws -> String
}

/// A failure of the underlying judge runner — the judge subprocess exited non-zero (auth, rate-limit,
/// model error, …). **Distinct from a judged FAIL:** it means the criterion could not be graded, so
/// the run loop classifies the trial as ungraded/failed rather than manufacturing a criterion FAIL
/// from diagnostic/empty output (preserving the measurement-vs-noise distinction).
public enum JudgeRunnerError: Error, Sendable, Equatable {
    case failed(exitCode: Int32, stderr: String)
}
