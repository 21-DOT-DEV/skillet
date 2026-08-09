import Testing
import Foundation
import EDDCore
@testable import IterateKit

@Suite("apply a reviewed draft — exactly, or not at all")
struct EditApplyTests {
    static let file = "# Guide\n\nAlways use the rule of three.\n\nKeep replies short.\n"

    func edit(_ excerpt: String, _ replacement: String, path: String = "SKILL.md") -> EditProposal {
        EditProposal(path: path, skillMdLines: "0", currentExcerpt: excerpt,
                     proposedText: replacement, rationale: "r", addresses: [])
    }

    func plan(_ edits: [EditProposal], selecting: [Int]? = nil,
              in text: String = EditApplyTests.file) -> EditApply.Plan {
        EditApply.plan(edits, selecting: selecting, in: text, editableFileName: "SKILL.md")
    }

    @Test("A passage appearing exactly once is placed where it actually is")
    func exactlyOnce() throws {
        guard case let .ready(placements) = plan([edit("Keep replies short.", "Be brief.")]) else {
            Issue.record("expected a ready plan"); return
        }
        #expect(placements.count == 1)
        #expect(placements[0].lines == "5", "the line span is derived from the match, not the draft")
        #expect(EditApply.apply(placements, to: Self.file).contains("Be brief."))
    }

    @Test("A passage that is no longer there is refused — this is how drift is caught")
    func missingPassage() {
        guard case let .refused(reasons) = plan([edit("Text that was edited away", "x")]) else {
            Issue.record("expected a refusal"); return
        }
        #expect(reasons == [.missing(index: 0)])
    }

    @Test("A passage appearing more than once is refused, with the count")
    func ambiguousPassage() {
        let text = "same line\nsame line\n"
        guard case let .refused(reasons) = plan([edit("same line", "x")], in: text) else {
            Issue.record("expected a refusal"); return
        }
        #expect(reasons == [.ambiguous(index: 0, count: 2, lines: ["1", "2"], capped: false)])
    }

    @Test("Two edits covering overlapping text are refused, not resolved")
    func overlappingEdits() {
        let edits = [edit("Always use the rule of three.", "A"), edit("the rule of three", "B")]
        guard case let .refused(reasons) = plan(edits) else { Issue.record("expected a refusal"); return }
        #expect(reasons == [.overlapping(index: 0, with: 1)])
    }

    @Test("Several edits apply in one pass, and later ones do not shift earlier ones")
    func severalEditsAtOnce() throws {
        // The replacement lengths differ from the originals on purpose: applied front-to-back, the
        // second placement's recorded position would be wrong by the time it was used.
        let edits = [edit("Always use the rule of three.", "Use three."),
                     edit("Keep replies short.", "Keep every reply as short as it can usefully be.")]
        guard case let .ready(placements) = plan(edits) else { Issue.record("expected ready"); return }
        let result = EditApply.apply(placements, to: Self.file)
        #expect(result == "# Guide\n\nUse three.\n\nKeep every reply as short as it can usefully be.\n")
    }

    @Test("A number that is not an edit in this draft is refused as a mistake in the request")
    func unknownIndex() {
        guard case let .refused(reasons) = plan([edit("Keep replies short.", "x")], selecting: [0, 4]) else {
            Issue.record("expected a refusal"); return
        }
        #expect(reasons == [.unknownIndex(4, available: 1)])
        #expect(reasons[0].isUsageMistake, "asking for an edit that isn't there is misuse, not drift")
    }

    @Test("A draft naming a file this version does not write is refused")
    func unsupportedPath() {
        guard case let .refused(reasons) = plan([edit("Keep replies short.", "x", path: "references/x.md")]) else {
            Issue.record("expected a refusal"); return
        }
        #expect(reasons == [.unsupportedPath(index: 0, path: "references/x.md")])
    }

    /// The property everything else rests on: one bad edit means no placements at all, so a caller
    /// cannot write a partial result even by mistake.
    @Test("One refused edit means no placements are produced for any of them")
    func oneRefusalStopsEverything() {
        let edits = [edit("Keep replies short.", "Be brief."),      // would apply cleanly
                     edit("Text that was edited away", "x")]        // has drifted
        guard case let .refused(reasons) = plan(edits) else {
            Issue.record("a valid edit alongside a drifted one must still refuse"); return
        }
        #expect(reasons == [.missing(index: 1)])
    }

    @Test("Selecting a subset applies only those edits")
    func subsetSelection() throws {
        let edits = [edit("Always use the rule of three.", "A"), edit("Keep replies short.", "B")]
        guard case let .ready(placements) = plan(edits, selecting: [1]) else {
            Issue.record("expected ready"); return
        }
        #expect(placements.map(\.index) == [1])
        let result = EditApply.apply(placements, to: Self.file)
        #expect(result.contains("Always use the rule of three."), "the unselected edit is untouched")
        #expect(result.contains("B"))
    }

    /// The result must not depend on what order placements arrive in. The first implementation edited
    /// the string in place, which meant reusing positions measured against text that had already
    /// changed — undefined in Swift, and it hung rather than producing wrong output.
    @Test("Applying is independent of the order the placements are given in")
    func orderIndependent() {
        let edits = [edit("Always use the rule of three.", "Use three."),
                     edit("Keep replies short.", "Keep every reply as short as it can usefully be.")]
        guard case let .ready(placements) = plan(edits) else { Issue.record("expected ready"); return }
        let forwards = EditApply.apply(placements, to: Self.file)
        let backwards = EditApply.apply(placements.reversed(), to: Self.file)
        #expect(forwards == backwards)
        #expect(forwards == "# Guide\n\nUse three.\n\nKeep every reply as short as it can usefully be.\n")
    }

    // MARK: - Windows line endings

    static let windowsFile = EditApplyTests.file.replacingOccurrences(of: "\n", with: "\r\n")

    /// A file checked out on Windows holds carriage returns; a model quotes it back with plain
    /// newlines, so a multi-line edit never matched. The tool said "no longer in the file — draft
    /// again", which is advice that cannot work: re-drafting produces the same mismatch.
    @Test("A multi-line edit applies to a file with Windows line endings")
    func appliesToWindowsFile() throws {
        let edits = [edit("Always use the rule of three.\n\nKeep replies short.", "Be brief.")]
        guard case let .ready(placements) = plan(edits, in: Self.windowsFile) else {
            Issue.record("a plain-newline edit must still match a carriage-return file"); return
        }
        let result = EditApply.apply(placements, to: Self.windowsFile)
        #expect(result.contains("Be brief."))
        #expect(!result.contains("\n\n"), "the file's own line endings must survive the write")
    }

    @Test("A replacement spanning lines is written in the file's own convention")
    func replacementKeepsFileConvention() throws {
        let edits = [edit("Keep replies short.", "Be brief.\nAlways.")]
        guard case let .ready(placements) = plan(edits, in: Self.windowsFile) else {
            Issue.record("expected ready"); return
        }
        let result = EditApply.apply(placements, to: Self.windowsFile)
        #expect(result.contains("Be brief.\r\nAlways."), "a plain newline would leave the file mixed")
    }

    /// Converting works both ways now, so a quoted passage carrying Windows line breaks matches a plain
    /// file rather than being refused. This used to be a refusal; making the conversion symmetric turned
    /// it into a success, which is the point.
    @Test("A quoted passage with Windows line breaks matches a plain file")
    func windowsQuoteMatchesPlainFile() throws {
        let edits = [edit("Always use the rule of three.\r\n\r\nKeep replies short.", "Be brief.")]
        guard case let .ready(placements) = plan(edits) else {
            Issue.record("converting should rescue this, not refuse it"); return
        }
        #expect(EditApply.apply(placements, to: Self.file).contains("Be brief."))
    }

    /// Files written on Macs before 2001 end a line with a carriage return and nothing else. Handling
    /// only the other two conventions meant every passage spanning two lines failed to match such a file
    /// and was refused as though the file had changed — it had not, and re-drafting hit the same wall.
    static let classicMacFile = EditApplyTests.file.replacingOccurrences(of: "\n", with: "\r")

    @Test("A multi-line edit applies to a file using carriage returns alone")
    func appliesToClassicMacFile() throws {
        let edits = [edit("Always use the rule of three.\n\nKeep replies short.", "Be brief.")]
        guard case let .ready(placements) = plan(edits, in: Self.classicMacFile) else {
            Issue.record("a plain-newline edit must match a carriage-return-only file too"); return
        }
        let result = EditApply.apply(placements, to: Self.classicMacFile)
        #expect(result.contains("Be brief."))
        #expect(!result.contains("\n"), "the file's own line endings must survive the write")
    }

    /// The half the review missed, and the worse half: this one **succeeded**. A single-line quote
    /// matched, so the edit applied — and wrote a plain newline into a file that uses carriage returns,
    /// leaving it using both at once. A refusal is visible; this was silent.
    @Test("A replacement spanning lines is written in carriage returns when that is the file's convention")
    func replacementKeepsClassicMacConvention() throws {
        let edits = [edit("Keep replies short.", "Be brief.\nAlways.")]
        guard case let .ready(placements) = plan(edits, in: Self.classicMacFile) else {
            Issue.record("expected ready"); return
        }
        let result = EditApply.apply(placements, to: Self.classicMacFile)
        #expect(result.contains("Be brief.\rAlways."))
        #expect(!result.contains("\n"), "a plain newline here leaves the file using two conventions at once")
    }

    /// Line numbers are counted by looking for line breaks. Counting only line feeds reported every match
    /// in a carriage-return file as line 1 — a confidently wrong location, which is worse than none.
    @Test("A match in a carriage-return file reports the line it is actually on")
    func lineNumbersCountCarriageReturns() {
        guard case let .found(_, lines) = ExcerptAnchor.locate("Keep replies short.", in: Self.classicMacFile) else {
            Issue.record("expected a match"); return
        }
        #expect(lines == "5", "the passage is on line 5, not line 1")
    }

    /// The fallback still exists for what converting cannot rescue: a file that mixes both conventions
    /// has no single convention to convert to. Saying which side carries the carriage returns matters
    /// because the remedy differs completely from the one for a file that has genuinely moved on.
    @Test("A file mixing both line-break conventions is diagnosed, not called drift")
    func mixedFileIsDiagnosed() {
        let mixed = "alpha\r\nbravo\ncharlie\r\n"
        guard case let .refused(reasons) = plan([edit("bravo\ncharlie", "x")], in: mixed) else {
            Issue.record("expected a refusal"); return
        }
        #expect(reasons == [.lineEndingsDiffer(index: 0, fileHasCarriageReturns: true)])
    }

    /// A replacement carrying Windows line breaks used to be written into a plain file unchanged,
    /// leaving the file mixing both conventions.
    @Test("A replacement is written in the file's own line-break convention, both ways round")
    func replacementAdoptsTheFileConvention() throws {
        guard case let .ready(plain) = plan([edit("Keep replies short.", "Be brief.\r\nStay brief.")]) else {
            Issue.record("expected ready"); return
        }
        let intoPlainFile = EditApply.apply(plain, to: Self.file)
        #expect(!intoPlainFile.contains("\r\n"), "a plain file must stay plain")

        guard case let .ready(crlf) =
            plan([edit("Keep replies short.", "Be brief.\nStay brief.")], in: Self.windowsFile) else {
            Issue.record("expected ready"); return
        }
        let intoWindowsFile = EditApply.apply(crlf, to: Self.windowsFile)
        #expect(intoWindowsFile.contains("Be brief.\r\nStay brief."), "a Windows file must stay Windows")
    }

    @Test("Genuine drift is still reported as drift, not as a line-ending problem")
    func realDriftIsNotMisdiagnosed() {
        guard case let .refused(reasons) = plan([edit("Text nobody wrote", "x")]) else {
            Issue.record("expected a refusal"); return
        }
        #expect(reasons == [.missing(index: 0)])
    }

    // MARK: - overlapping duplicates

    /// Three identical bullet lines is ordinary markdown. A passage covering two of them matches at two
    /// overlapping places — and the old scan skipped past each match before looking again, so it found
    /// one, called the passage unique, and the tool replaced the first while reporting success. That is
    /// precisely the ambiguity the exactly-once rule exists to refuse.
    @Test("A passage that matches at overlapping positions is ambiguous, not unique")
    func overlappingMatchesAreAmbiguous() {
        let text = "# Guide\n\n- Keep it short.\n- Keep it short.\n- Keep it short.\n"
        guard case let .refused(reasons) = plan([edit("- Keep it short.\n- Keep it short.", "- Be brief.")],
                                                in: text) else {
            Issue.record("two overlapping positions must refuse, not pick the first"); return
        }
        guard case let .ambiguous(index, count, lines, capped) = reasons[0] else {
            Issue.record("expected an ambiguity refusal, got \(reasons)"); return
        }
        #expect(index == 0)
        #expect(count == 2, "both positions must be counted, not just the non-overlapping one")
        #expect(lines == ["3-4", "4-5"], "the locations are what tells identical matches apart")
        #expect(!capped)
    }

    @Test("A refusal names where the duplicates are, capped so a repeated passage cannot bury the message")
    func ambiguityNamesLocations() {
        let text = String(repeating: "ab", count: 40)   // "ab" matches at 40 positions
        guard case let .refused(reasons) = plan([edit("ab", "x")], in: text),
              case let .ambiguous(_, count, lines, _) = reasons[0] else {
            Issue.record("expected an ambiguity refusal"); return
        }
        #expect(count == 40)
        #expect(lines.count == 5, "at most a handful of locations are listed")
    }

    @Test("A genuinely unique passage is still accepted")
    func uniqueStillApplies() throws {
        guard case let .ready(placements) = plan([edit("Keep replies short.", "Be brief.")]) else {
            Issue.record("the stricter count must not refuse a genuinely unique passage"); return
        }
        #expect(placements.count == 1)
    }
}
