import Foundation

/// One user turn judged a substantive correction — the human fixing or redirecting the assistant's work.
public struct CorrectiveTurn: Sendable, Equatable {
    /// 0-based ordinal among **all** user turns (the opening prompt is 0 and is never emitted).
    public let index: Int
    /// The trimmed user-turn text.
    public let text: String
    public init(index: Int, text: String) {
        self.index = index
        self.text = text
    }
}

/// Recall-first corrective-turn detection over the normalized `Trace` (harness-independent by
/// construction — design §9.3). Ported from the predecessor's `TranscriptFeedback`, but reading
/// `Trace.turns` instead of parsing rendered `## User` headers.
///
/// Recall-first (D-3): drop the opening prompt (a task, not a correction) and bare continuations
/// (`continue`/`go`/…); keep every other substantive user turn "for the human/judge to validate." The
/// downstream is the paid axial-coding judge (Phase 4), so a high-recall filter is correct — a precision
/// word-list would discard real corrections before they can be coded. The diff-revert half is a later
/// phase. This never *invents* corrections: only turns the human actually made are considered.
public enum CorrectiveTurns {
    /// Bare continuations that carry no corrective signal (trim-tolerant, case-insensitive).
    static let continuations: Set<String> = ["continue", "go", "go ahead", "proceed"]

    public static func detect(in trace: Trace) -> [CorrectiveTurn] {
        var out: [CorrectiveTurn] = []
        var ordinal = 0
        for turn in trace.turns where turn.role == .user {
            defer { ordinal += 1 }
            guard ordinal > 0 else { continue }                                   // opening prompt
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !continuations.contains(text.lowercased()) else { continue }
            out.append(CorrectiveTurn(index: ordinal, text: text))
        }
        return out
    }
}
