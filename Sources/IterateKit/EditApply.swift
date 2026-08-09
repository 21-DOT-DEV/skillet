import Foundation
import EDDCore

/// Putting a reviewed draft into a file, **exactly or not at all**.
///
/// Each edit carries a passage that must appear in the file exactly once. Between the draft being
/// written and being applied, the file may have changed — so a passage can now match nothing, or match
/// twice. Every selected edit is checked *before* anything is produced, and the result is either a
/// complete set of placements or the reasons it refused. There is no partial answer, deliberately:
///
/// - "Nothing happened" is a state that always recovers. A half-applied file matches neither the
///   original nor the draft.
/// - A draft claims *these tests should start passing*. Apply some of it silently and that claim now
///   describes something you did not do: you re-measure, the tests do not flip, and you discard a fix
///   that was correct. A false negative is the most expensive error this loop can make.
///
/// Pure — no filesystem, no processes. The caller reads the file, decides the repository is safe to
/// touch, and writes the result.
public enum EditApply {
    /// One verified edit: where it goes, and what replaces it.
    public struct Placement: Equatable, Sendable {
        public let index: Int
        public let range: Range<String.Index>
        public let lines: String
        public let replacement: String
    }

    public enum Refusal: Equatable, Sendable {
        /// A number that isn't an edit in this draft. Distinct from the others because it is a mistake
        /// in what you asked for, not a change in the world — the caller reports it as misuse.
        case unknownIndex(Int, available: Int)
        case missing(index: Int)
        /// The quoted text would have matched if the two sides agreed about line endings. Reported
        /// separately because "no longer in the file — draft again" is *wrong* here: the file has not
        /// changed, and re-drafting produces the same mismatch, so that advice loops forever.
        case lineEndingsDiffer(index: Int, fileHasCarriageReturns: Bool)
        case ambiguous(index: Int, count: Int, lines: [String], capped: Bool)
        /// Two selected edits cover overlapping text, so applying either changes what the other meant.
        case overlapping(index: Int, with: Int)
        /// The draft names a file this version does not write.
        case unsupportedPath(index: Int, path: String)

        public var isUsageMistake: Bool { if case .unknownIndex = self { return true }; return false }
    }

    /// What a verification produced: every placement, or every reason it refused. Never a mixture —
    /// that is the whole point.
    public enum Plan: Equatable, Sendable {
        case ready([Placement])
        case refused([Refusal])
    }

    /// Verify a selection against `text`. `selection` is `nil` for "every edit in the draft".
    public static func plan(_ edits: [EditProposal], selecting selection: [Int]?,
                            in text: String, editableFileName: String) -> Plan {
        let indices = selection ?? Array(edits.indices)
        var refusals: [Refusal] = []
        var placements: [Placement] = []

        for index in indices {
            guard edits.indices.contains(index) else {
                refusals.append(.unknownIndex(index, available: edits.count)); continue
            }
            let edit = edits[index]
            guard edit.path == editableFileName else {
                refusals.append(.unsupportedPath(index: index, path: edit.path)); continue
            }
            let excerpt = ExcerptAnchor.matchingLineBreaks(of: edit.currentExcerpt, to: text)
            switch ExcerptAnchor.locate(excerpt, in: text) {
            case let .found(range, lines):
                // The replacement gets the same treatment, so the file keeps one convention throughout.
                placements.append(Placement(index: index, range: range, lines: lines,
                                            replacement: ExcerptAnchor.matchingLineBreaks(of: edit.proposedText, to: text)))
            case .missing:
                // Say which it is. If ignoring line endings entirely *would* have matched, then the file
                // has not drifted — the two sides simply disagree about newlines, and the remedy is
                // completely different from "draft again".
                if case .found = ExcerptAnchor.locate(ExcerptAnchor.withPlainLineBreaks(edit.currentExcerpt), in: ExcerptAnchor.withPlainLineBreaks(text)) {
                    refusals.append(.lineEndingsDiffer(index: index,
                                                       fileHasCarriageReturns: text.contains("\r\n")))
                } else {
                    refusals.append(.missing(index: index))
                }
            case let .ambiguous(count, lines, capped):
                refusals.append(.ambiguous(index: index, count: count, lines: lines, capped: capped))
            }
        }

        // Overlap is only knowable once every placement is known, so it is checked last. Compared
        // pairwise on a small set — a draft holds a handful of edits, not thousands.
        for (a, first) in placements.enumerated() {
            for second in placements[(a + 1)...] where first.range.overlaps(second.range) {
                refusals.append(.overlapping(index: min(first.index, second.index),
                                             with: max(first.index, second.index)))
            }
        }

        return refusals.isEmpty ? .ready(placements.sorted { $0.index < $1.index }) : .refused(refusals)
    }

    /// Build the new text by walking the original once, front to back, taking the untouched stretches
    /// between placements and substituting the rest.
    ///
    /// **Nothing is mutated in place, deliberately.** Every placement's position was measured against
    /// the original text, and in Swift *any* mutation invalidates the positions you already hold — so
    /// editing the string as you go and reusing those positions is undefined, not merely fragile. It
    /// does not fail cleanly either: a wrong ordering hangs rather than producing wrong output, which is
    /// how this was found. Reading from an untouched original removes the hazard rather than ordering
    /// around it, and the result no longer depends on the order placements arrive in.
    public static func apply(_ placements: [Placement], to text: String) -> String {
        var result = ""
        var cursor = text.startIndex
        for placement in placements.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            result += text[cursor..<placement.range.lowerBound]
            result += placement.replacement
            cursor = placement.range.upperBound
        }
        result += text[cursor...]
        return result
    }
}
