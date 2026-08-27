import EDDCore
import Foundation

/// The free, model-free static gate over `SKILL.md` source (design §6.1). Pure: it maps a parsed
/// ``SkillSource`` plus the `[lint]` knobs to `[Diagnostic]`, with no I/O and no YAML — so it is
/// interop-free and isolated-testable. F4 ships the three error-tier rules; the catalog is additive.
public struct Linter: Sendable {
    public init() {}

    /// Run every enabled rule over one skill. Ids listed in `config.disable` are skipped.
    public func lint(_ source: SkillSource, config: SkilletConfig.Lint = .init()) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        func enabled(_ id: String) -> Bool { !config.disable.contains(id) }

        if enabled(Rule.descriptionLength) { checkDescriptionLength(source, into: &diagnostics) }
        if enabled(Rule.bodyBudget) { checkBodyBudget(source, config: config, into: &diagnostics) }
        if enabled(Rule.hasEvals) { checkHasEvals(source, into: &diagnostics) }
        if enabled(Rule.nameShape) { checkNameShape(source, into: &diagnostics) }
        return diagnostics
    }

    /// Stable rule ids (design §6.1) — held in one place so disable-matching and emission can't drift.
    enum Rule {
        static let descriptionLength = "SKILL-L001"
        static let bodyBudget = "SKILL-L003"
        static let hasEvals = "SKILL-L009"
        static let nameShape = "SKILL-L012"
    }

    // MARK: - L001 frontmatter / description length

    private func checkDescriptionLength(_ source: SkillSource, into diagnostics: inout [Diagnostic]) {
        guard let frontmatter = source.frontmatter else {
            diagnostics.append(Diagnostic(
                id: Rule.descriptionLength, tier: .error, skill: source.name,
                message: "frontmatter is missing or unparseable",
                fixHint: "open SKILL.md with a valid `---` YAML frontmatter block defining `name` and `description`"
            ))
            return
        }
        guard let description = frontmatter.description else { return }   // a missing description is F3 doctor's job
        // Count Unicode code points (no normalization) after trimming — matching Anthropic's canonical
        // `len(description.strip()) > 1024` (skill-creator quick_validate.py:82). Code points, not
        // grapheme clusters, so combining / zero-width padding can't slip under the limit.
        let length = description.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        if length > 1024 {
            diagnostics.append(Diagnostic(
                id: Rule.descriptionLength, tier: .error, skill: source.name,
                message: "description is \(length) characters; the limit is 1024",
                fixHint: "tighten the description to ≤1024 characters, or move detail into references/"
            ))
        }
    }

    // MARK: - L003 body budget

    private func checkBodyBudget(_ source: SkillSource, config: SkilletConfig.Lint, into diagnostics: inout [Diagnostic]) {
        let lines = bodyLineCount(source.body)
        if lines > config.bodyErrorLines {
            diagnostics.append(Diagnostic(
                id: Rule.bodyBudget, tier: .error, skill: source.name,
                message: "body is \(lines) lines (excluding frontmatter and code); the error budget is \(config.bodyErrorLines)",
                fixHint: "move detail into references/ files and keep SKILL.md to the essentials"
            ))
        } else if lines > config.bodyWarnLines {
            diagnostics.append(Diagnostic(
                id: Rule.bodyBudget, tier: .warn, skill: source.name,
                message: "body is \(lines) lines (excluding frontmatter and code); the warn budget is \(config.bodyWarnLines)",
                fixHint: "consider moving detail into references/ files"
            ))
        }
    }

    /// Body lines excluding fenced code blocks (and their fence markers). The frontmatter is already
    /// stripped upstream. A *terminal* newline is a line terminator, not a trailing blank line, so it
    /// isn't over-counted (a body of exactly N content lines counts as N). Fences track the opener's
    /// marker character + run length: per CommonMark, only a line of the same marker, at least as long,
    /// with nothing after it, closes the block — so mixed `~~~`/``` markers and fence-like content lines
    /// don't mis-toggle. Pinned by tests; refine if it proves noisy (design §6.1).
    private func bodyLineCount(_ body: String) -> Int {
        var text = body
        if text.hasSuffix("\n") { text.removeLast() }   // terminator, not an extra blank line
        if text.isEmpty { return 0 }
        var count = 0
        var openFence: (marker: Character, length: Int)?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let fence = fenceMarker(String(raw).trimmingCharacters(in: .whitespaces))
            if let open = openFence {
                // Only a same-marker run ≥ the opener's length, with nothing trailing, closes the block.
                if let fence, fence.marker == open.marker, fence.length >= open.length, fence.rest.isEmpty {
                    openFence = nil
                }
                continue   // lines within a fence (and the fences themselves) don't count
            }
            if let fence {
                openFence = (fence.marker, fence.length)
                continue
            }
            count += 1
        }
        return count
    }

    /// If `trimmed` is a fenced-code marker line, returns its marker char (`` ` `` or `~`), run length
    /// (≥3), and the remainder after the run — an opener may carry an info string, a closer may not.
    private func fenceMarker(_ trimmed: String) -> (marker: Character, length: Int, rest: String)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix { $0 == first }
        guard run.count >= 3 else { return nil }
        return (first, run.count, String(trimmed.dropFirst(run.count)))
    }

    // MARK: - L012 name shape

    /// **The folder a skill lives in has to be a legal skill name, and has to survive being typed.**
    ///
    /// The published rule for a skill's name is lowercase letters, digits and hyphens, no hyphen at
    /// either end, no doubled hyphen, at most 64 characters — and the name must match the folder. This
    /// checks the **folder** name, because that is the word this tool prints into the commands it tells
    /// you to run, and because the two are allowed to disagree here today: a folder called `-demo` whose
    /// SKILL.md declares `name: demo` passed every check while the printed command was unusable.
    ///
    /// **A leading hyphen is the error, the rest are warnings.** Measured: a folder named `-demo` makes
    /// this tool print `skillet run -demo`, and running that gives *"Unknown option '-demo'"* — the word
    /// is read as a switch rather than a name. That is a broken recommendation, not a style point. An
    /// uppercase letter or an underscore is off-spec but harms nothing you can run, so it warns.
    private func checkNameShape(_ source: SkillSource, into diagnostics: inout [Diagnostic]) {
        let name = source.name
        guard !name.isEmpty else { return }   // an unnamed folder is not something this rule can describe

        if name.hasPrefix("-") {
            diagnostics.append(Diagnostic(
                id: Rule.nameShape, tier: .error, skill: name,
                message: "the folder name '\(name)' starts with a hyphen, so commands naming this skill "
                    + "are read as options rather than as a name",
                fixHint: "rename the folder so it starts with a letter or a digit — a leading hyphen also "
                    + "breaks the published skill-name rule"))
        }
        // Everything else the published rule forbids. Reported together so one rename settles all of it,
        // rather than making you fix a name, re-run, and be told about the next fault in the same word.
        var offSpec: [String] = []
        if name.range(of: "^[a-z0-9-]+$", options: .regularExpression) == nil {
            offSpec.append("may only contain lowercase letters, digits and hyphens")
        }
        if name.hasSuffix("-") { offSpec.append("may not end with a hyphen") }
        if name.contains("--") { offSpec.append("may not contain two hyphens in a row") }
        if name.count > 64 { offSpec.append("is \(name.count) characters, over the 64-character limit") }
        if !offSpec.isEmpty {
            diagnostics.append(Diagnostic(
                id: Rule.nameShape, tier: .warn, skill: name,
                message: "the folder name '\(name)' \(offSpec.joined(separator: "; and "))",
                fixHint: "rename the folder to lowercase words joined by single hyphens, e.g. "
                    + "review-pull-request — a skill's name must match its folder"))
        }
    }

    // MARK: - L009 has-evals

    private func checkHasEvals(_ source: SkillSource, into diagnostics: inout [Diagnostic]) {
        guard let evals = source.evals else {
            // Distinguish a genuinely-absent file from one that exists but won't parse, so the message
            // isn't misleading. Both are error-tier.
            let (message, fixHint) = source.evalsPresent
                ? ("evals.json exists but is not valid JSON",
                   "fix evals.json so it parses as the skill-creator 2.0 object or the legacy array")
                : ("no evals.json found",
                   "add evaluations/evals.json with at least 3 cases covering the skill's core trigger paths")
            diagnostics.append(Diagnostic(id: Rule.hasEvals, tier: .error, skill: source.name, message: message, fixHint: fixHint))
            return
        }
        let count = evals.caseCount
        if count < 3 {
            diagnostics.append(Diagnostic(
                id: Rule.hasEvals, tier: .warn, skill: source.name,
                message: "evals.json has \(count) case\(count == 1 ? "" : "s"); aim for at least 3",
                fixHint: "add more eval cases to evaluations/evals.json"
            ))
        }
    }
}
