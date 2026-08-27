import Foundation
import EDDCore

/// Turning `--edits 2 0` into the list a command acts on — the same three judgements, once, for every
/// command that narrows a draft.
///
/// **Why shared.** Two of the three checks were written twice and the third only once. The command that
/// writes your files refuses a repeated number; the command that proves an edit did not, so `--edits 0 0`
/// slipped past it into the overlap test, which then reported that *"edits 0 and 0 cover overlapping
/// text"* — an edit cannot overlap itself — and advised applying them *"one at a time with --edits"*, the
/// flag just used. It also left the wrong number: `5`, meaning a deliberate safety check said no, for
/// something that was simply mistyped. That is the seventh time in this feature a check lived in one
/// command and was absent from its sibling.
///
/// **One wording, one word of difference.** The two commands used to say different things about the same
/// mistake, each better in a different way: one named the flag and the count, the other said what
/// dropping the flag would do. Neither was worth keeping over the other, so this says all of it — and the
/// only genuine difference, that one command *applies* and the other *proves*, is a single word supplied
/// by the caller. Human text carries no compatibility promise here (design P7), so nothing was owed to
/// either old wording; what is owed is the rule that a message says what went wrong and what fixes it
/// (design P6).
enum EditSelection {
    /// What the command will do with the edits — the one word the shared sentence cannot know.
    enum Verb: String {
        /// Writes them into your working tree.
        case apply
        /// Measures them in a throwaway copy, changing nothing.
        case prove
    }

    /// The edits to act on, in a canonical order with no repeats. An empty request means all of them.
    ///
    /// Returning the full list rather than "nothing was asked for" is deliberate: every later use — what
    /// is planned, what is printed, what the record says, and which command is offered at the end — must
    /// agree about which edits were involved, and they can only agree if there is one list.
    static func resolve(_ requested: [Int], in draft: String, count: Int, verb: Verb) throws -> [Int] {
        guard !requested.isEmpty else { return Array(0..<count) }
        // **Checked here, the first moment the valid range exists**, because the draft is what defines
        // it. Checked later, an unrelated uncommitted file answered first: the same typo produced a clear
        // "no edit 7" on a clean working copy and an unhelpful "you have uncommitted changes" otherwise,
        // so you fixed the wrong thing and met the real mistake on a second run.
        if let outside = requested.first(where: { $0 < 0 || $0 >= count }) {
            throw EDDError.usage(
                message: "--edits \(outside) is not an edit in \(draft) (it has \(count))",
                remedy: count == 1
                    ? "this draft has one edit, numbered 0 — use `--edits 0`, or drop --edits to \(verb.rawValue) it"
                    : "pick from 0–\(count - 1), or drop --edits to \(verb.rawValue) all \(count)")
        }
        // Naming the same edit twice is a slip in the command, almost always a fumbled second number.
        // Refusing costs one retype; acting on it once would do less than was asked.
        var seen = Set<Int>()
        if let repeated = requested.first(where: { !seen.insert($0).inserted }) {
            throw EDDError.usage(
                message: "--edits names edit \(repeated) more than once",
                remedy: "list each edit at most once — for two edits that is `--edits 0 1`")
        }
        return requested.sorted()
    }

    /// The selection to hand the applying engine: `nil` when it is everything, which is what that engine
    /// already means by "no selection", so a full list and no list cannot diverge.
    static func planSelection(_ chosen: [Int], count: Int) -> [Int]? {
        chosen == Array(0..<count) ? nil : chosen
    }
}
