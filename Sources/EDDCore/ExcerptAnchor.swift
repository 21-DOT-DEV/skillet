import Foundation

/// Finding a quoted passage in a file, with the rule both halves of the fix loop depend on: **it must
/// appear exactly once.**
///
/// Drafting uses it to check a passage a model proposed before recording it. Applying uses it against
/// the file as it is *now*, which is how drift is caught — the file changed, so the passage no longer
/// appears, or appears twice, and the edit is refused rather than guessed at.
///
/// Two copies of a rule this load-bearing is how they drift apart, so it lives here and both call it.
/// It returns the matched **range** — applying needs to splice text, not just describe where it was —
/// with the human-readable line label derived from that same match rather than tracked separately.
public enum ExcerptAnchor {
    public enum Match: Equatable, Sendable {
        /// `lines` is `"142"` or `"142-145"`, derived from the match — never taken on trust.
        case found(range: Range<String.Index>, lines: String)
        case missing
        /// `capped` is true when counting stopped early, so the message can say "at least N".
        /// `lines` names where the first few matches are, so the refusal can be acted on rather than
        /// merely understood — every match has *identical* text by definition, so the locations are the
        /// only distinguishing information there is.
        case ambiguous(count: Int, lines: [String], capped: Bool)
    }

    /// Counting stops here so a pathological passage-and-file pair cannot make this expensive. At the
    /// cap the caller says "at least N", which stays true rather than under-reporting.
    static let scanCap = 1_000

    /// How many locations a refusal names. A short passage can match hundreds of times; listing them all
    /// would bury the message it belongs to.
    static let shownLocations = 5

    /// Rewrite `snippet`'s line breaks to match `text`'s own convention.
    ///
    /// A file checked out on Windows holds carriage returns; a model quotes it back with plain
    /// newlines, so any passage spanning more than one line fails to match. **This is a translation,
    /// not a tolerance** — every line break has exactly one correct representation in the target file,
    /// so afterwards the match is as strict as ever.
    ///
    /// It lives here, beside the match rule itself, because both halves of the loop need it: drafting
    /// checks a model's quoted passage against the file, and applying checks it again later. It was
    /// briefly only on the applying side, which left the paid drafting step dropping every multi-line
    /// edit on a Windows checkout and advising a re-draft that hit the same wall.
    /// How a file marks the end of a line. **Three, not two.** Handling only the first two meant a file
    /// using the third had every multi-line passage fail to match, and the refusal said "the file changed
    /// since this draft was made; draft again" — the file had not changed, and drafting again hit the same
    /// wall. Worse, it was not only refusals: a *replacement* spanning two lines was written into such a
    /// file with plain newlines and left it using both conventions at once, which succeeded silently.
    /// Reduced-to-plain-then-adopt is how the other two are already handled; this adds the third to the
    /// same mechanism rather than a new one, and matches how text tooling has treated all three since
    /// universal newline handling became standard.
    public enum LineBreak {
        /// A carriage return followed by a line feed — Windows.
        case pair
        /// A carriage return alone — Macs before 2001.
        case carriageReturn
        /// A line feed alone — Unix and modern macOS.
        case lineFeed

        var text: String {
            switch self {
            case .pair: "\r\n"
            case .carriageReturn: "\r"
            case .lineFeed: "\n"
            }
        }

        /// **Order matters.** A file containing the pair contains a carriage return too, so the pair has
        /// to be ruled out first or every Windows file would be read as the older convention.
        public static func of(_ text: String) -> LineBreak {
            if text.contains("\r\n") { return .pair }
        if text.contains("\r") { return .carriageReturn }
                return .lineFeed
        }
    }

    public static func matchingLineBreaks(of snippet: String, to text: String) -> String {
        // Reduce to one convention first, so nothing is converted twice, then adopt the file's.
        // **Both directions.** This used to return early when the file used plain line breaks, which
        // meant a replacement carrying Windows ones was written into a plain file unchanged and left it
        // mixing the two. A file cannot want two conventions, and the code already converted the other
        // way round, so only half the rule existed.
        let plain = withPlainLineBreaks(snippet)
        let wanted = LineBreak.of(text)
        guard wanted != .lineFeed else { return plain }
        return plain.replacingOccurrences(of: "\n", with: wanted.text)
    }

    /// Both sides reduced to plain newlines — used only to tell "the line breaks disagree" apart from
    /// "this text is genuinely gone", which need opposite advice.
    ///
    /// The pair is collapsed **before** the lone carriage return, so a Windows line break becomes one
    /// plain newline rather than two.
    public static func withPlainLineBreaks(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    public static func locate(_ excerpt: String, in text: String) -> Match {
        guard !excerpt.isEmpty else { return .missing }
        // Count **every** occurrence, not just the first two: the refusal exists to help someone narrow
        // the quoted text, and "appears 2 times" when it appears 9 is actively misleading.
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while ranges.count < scanCap, let found = text.range(of: excerpt, range: searchStart..<text.endIndex) {
            ranges.append(found)
            // **Resume one character on, not past the whole match.** Skipping to the end of a match hides
            // overlapping ones — and overlap is ordinary here, not exotic: three identical bullet lines
            // and a passage covering two of them matches at two places. Counting non-overlapping
            // occurrences called that unique, so the tool replaced the first and reported success, which
            // is exactly the ambiguity this rule exists to refuse. What matters is how many *positions*
            // the passage could be replaced at, and that is what this counts.
            guard found.lowerBound < text.endIndex else { break }
            searchStart = text.index(after: found.lowerBound)
        }
        guard let only = ranges.first else { return .missing }
        if ranges.count > 1 {
            return .ambiguous(count: ranges.count,
                              lines: ranges.prefix(shownLocations).map { lineLabel(of: $0, in: text) },
                              capped: ranges.count == scanCap)
        }
        return .found(range: only, lines: lineLabel(of: only, in: text))
    }

    /// `142`, or `142-145` when the passage spans lines.
    public static func lineLabel(of range: Range<String.Index>, in text: String) -> String {
        // Counted through the same reduction the matching uses, so a line break of **any** convention
        // counts as one. Counting line feeds alone reported every match in a carriage-return file as
        // line 1, which is a confidently wrong location rather than a missing one.
        let before = withPlainLineBreaks(String(text[text.startIndex..<range.lowerBound]))
        let startLine = before.filter { $0 == "\n" }.count + 1
        let endLine = startLine + withPlainLineBreaks(String(text[range])).filter { $0 == "\n" }.count
        return startLine == endLine ? "\(startLine)" : "\(startLine)-\(endLine)"
    }
}
