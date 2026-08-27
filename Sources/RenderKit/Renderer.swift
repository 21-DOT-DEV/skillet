import Foundation
import EDDCore

/// Whether to render for humans (TTY tables/prose) or machines (`--json`).
public enum OutputMode: Sendable {
    case human
    case json
}

/// Turns domain payloads into a ``Rendering`` (stdout/stderr split), honoring the output mode and
/// color policy. Pure: it returns strings rather than writing, so every branch is unit-testable.
public struct Renderer: Sendable {
    /// **Measurements print the same way on every machine.** A figure shown as `+0.50` here is the same
    /// figure the saved results file records, and this table is routinely pasted into notes and issues
    /// and compared between people — so a machine whose region writes `0,50`, or groups a four-figure
    /// count as `1,100`, would make two readers of the same run disagree about what it said, and would
    /// change how many characters a number takes in columns aligned by width.
    ///
    /// Terminal output is for people and promises nothing, so following the reader's region would be
    /// allowed. It is not done because the one well-known command-line tool that did it withdrew the
    /// behaviour after complaints from users in exactly those regions, whose own data used dots.
    static let neutralNumbers = Locale(identifier: "en_US_POSIX")

    public let mode: OutputMode
    public let color: ColorPolicy

    public init(mode: OutputMode, color: ColorPolicy) {
        self.mode = mode
        self.color = color
    }

    /// The root command's output: the loop overview (human) or the `skillet.root/1` payload (json).
    public func renderRoot(_ info: RootInfo) throws -> Rendering {
        switch mode {
        case .json:
            return Rendering(stdout: try SkilletJSON.encode(info) + "\n")
        case .human:
            return Rendering(stdout: humanRoot(info))
        }
    }

    /// An error: human "what/why/fix" (human) or the `skillet.error/1` payload (json) — both to
    /// stderr, since an error is never the command's primary data.
    public func renderError(_ error: EDDError) -> Rendering {
        switch mode {
        case .json:
            let json = (try? SkilletJSON.encode(ErrorPayload(error))) ?? #"{"schema":"skillet.error/1"}"#
            return Rendering(stderr: json + "\n")
        case .human:
            return Rendering(stderr: humanError(error))
        }
    }

    /// `skillet init`'s output: a created/skipped summary (human) or the `skillet.init/1` payload (json).
    public func renderInit(_ report: InitReport, nextSteps: [String]) throws -> Rendering {
        switch mode {
        case .json:
            return Rendering(stdout: try SkilletJSON.encode(report) + "\n")
        case .human:
            return Rendering(stdout: humanInit(report, nextSteps: nextSteps))
        }
    }

    /// `skillet lint`'s output: the diagnostics table + fix hints + a tier summary (human), or the
    /// `skillet.lint/1` payload (json).
    public func renderLint(_ report: LintReport, nextSteps: [String]) throws -> Rendering {
        switch mode {
        case .json:
            return Rendering(stdout: try SkilletJSON.encode(report) + "\n")
        case .human:
            return Rendering(stdout: humanLint(report, nextSteps: nextSteps))
        }
    }

    /// `skillet run`'s output: the per-eval PASS/FAIL/FLAKY table + aggregate `pass^k` (human), or the
    /// `skillet.run/1` payload (json).
    public func renderRun(_ report: RunReport, nextSteps: [String] = []) throws -> Rendering {
        switch mode {
        case .json:
            return Rendering(stdout: try SkilletJSON.encode(report) + "\n")
        case .human:
            return Rendering(stdout: humanRun(report, nextSteps: nextSteps))
        }
    }

    /// `skillet doctor`'s output: per-check `✓/!/✗` rows with a fix line under each failure (human),
    /// or the `skillet.doctor/1` payload (json). Warnings render but never fail — the exit decision
    /// is the report's (`DoctorReport.exitCode`), not the renderer's.
    public func renderDoctor(_ report: DoctorReport, nextSteps: [String] = []) throws -> Rendering {
        switch mode {
        case .json:
            return Rendering(stdout: try SkilletJSON.encode(report) + "\n")
        case .human:
            return Rendering(stdout: humanDoctor(report, nextSteps: nextSteps))
        }
    }

    /// `skillet score`'s output (F17): the findings table + a summary line (human), or the
    /// `skillet.score/1` payload (json). The SARIF surface bypasses the renderer — the command emits
    /// `SarifDocument.jsonString()` straight to stdout, since `Renderer` models only `.human`/`.json`.
    public func renderScore(_ report: ScoreReport, nextSteps: [String] = []) throws -> Rendering {
        switch mode {
        case .json:
            return Rendering(stdout: try SkilletJSON.encode(report) + "\n")
        case .human:
            return Rendering(stdout: humanScore(report, nextSteps: nextSteps))
        }
    }

    /// `skillet triage`'s output (F33): per skill — staleness/coverage notes, the ranked cluster
    /// table with routing hypotheses, friction joins, disclosures — or the `skillet.triage/1`
    /// payload (json). A reporter: the renderer never decides an exit code.
    public func renderTriage(_ report: TriageReport, nextSteps: [String] = []) throws -> Rendering {
        switch mode {
        case .json:
            return Rendering(stdout: try SkilletJSON.encode(report) + "\n")
        case .human:
            return Rendering(stdout: humanTriage(report, nextSteps: nextSteps))
        }
    }

    /// `skillet iterate` (F43). The before-and-after table, the average difference with its error bar,
    /// and the verdict.
    ///
    /// **Every row shows both measurements**, so a reader can see what still fails rather than trusting a
    /// summary. A drop that sits inside run-to-run variation is marked `(varies)` — it still blocks, and
    /// the mark exists so nobody mistakes noise for damage or damage for noise.
    public func renderIterate(_ report: IterateReport, keptCopy: String?,
                              landCommand: String) throws -> Rendering {
        if case .json = mode { return Rendering(stdout: try SkilletJSON.encode(report) + "\n") }
        // **The column grows to fit the names, rather than cutting them off.** Padding to a fixed width
        // silently truncates anything longer, so two evals whose names share a long prefix printed as the
        // same row — and the reader has no way to tell which is which. Bounded so one very long name
        // cannot push the numbers off the screen; past that bound it is shortened *visibly*.
        let idWidth = min(max(24, report.comparison.perEval.map(\.id.count).max() ?? 0), 48)
        var lines = ["iterate — \(report.skill)",
                     "  draft            \(report.proposals)",
                     "  edits            \(report.edits.map(String.init).joined(separator: ", "))",
                     "",
                     "  " + "EVAL".padding(toLength: idWidth, withPad: " ", startingAt: 0)
                         + "  BEFORE   AFTER    Δ"]
        for row in report.comparison.perEval {
            let before = "\(row.beforePasses)/\(row.beforeRecorded)"
            let after = "\(row.afterPasses)/\(row.afterRecorded)"
            // **A difference too small to print is not the same as no difference.** Rounding to two
            // places turned a real change of 0.004 into `+0.00 ▲` and a real drop into `-0.00 ▼` — a
            // number that reads as nothing beside an arrow saying otherwise. Below what two places can
            // show, the size is written as a bound instead, and the arrow — which is never in doubt —
            // stays.
            let rounded = (row.delta * 100).rounded() / 100
            let delta = row.delta == 0 ? "—"
                : (rounded == 0 ? (row.delta > 0 ? "<+0.01" : ">-0.01") : String(format: "%+.2f", locale: Self.neutralNumbers, row.delta))
            let mark = row.delta < 0 ? " ▼" : (row.delta > 0 ? " ▲" : "")
            lines.append("  " + Self.fitted(row.id, to: idWidth)
                + "  " + before.padding(toLength: 8, withPad: " ", startingAt: 0)
                + " " + after.padding(toLength: 8, withPad: " ", startingAt: 0)
                + " " + delta + mark + (row.noisy ? " (varies between runs)" : ""))
        }
        let spread = report.comparison.standardError.map { String(format: " ± %.2f", locale: Self.neutralNumbers, $0) }
            ?? " (too few evals to state uncertainty)"
        lines.append("")
        // Same treatment as the rows above: an average too small to show at two places is written as a
        // bound rather than as a zero it is not.
        let mean = report.comparison.meanDelta
        let meanRounded = (mean * 100).rounded() / 100
        let meanText = mean != 0 && meanRounded == 0
            ? (mean > 0 ? "<+0.01" : ">-0.01") : String(format: "%+.2f", locale: Self.neutralNumbers, mean)
        // **An average over nothing is not printed as an average.** When no test ran on either side there
        // is no change to state, and the arithmetic still yields `+0.00` — which next to a repeat count of
        // zero reads as "measured, and it made no difference" rather than "nothing was measured". The
        // measuring command already refuses to state its own headline figure on exactly these grounds;
        // this said it in a way only someone who knew the code would catch. Same wording as the sibling,
        // so the two are recognisably one rule.
        lines.append(report.comparison.anythingMeasured
            ? "  average change   " + meanText + spread + "  (observed k=\(report.observedK))"
            : "  average change   unmeasurable (k=\(report.observedK)) — no test recorded a single run")
        // **The caveat qualifies the instrument, so it travels with both answers.** It used to appear
        // only on a proven verdict, contradicting this report's own documentation — and a blocked verdict
        // is exactly when it matters, since an unchecked grader may be why you are being told not to
        // ship. Parenthesised so it qualifies the grader rather than competing with the conclusion:
        // "not proven; provisional" hedges twice and muddies both.
        let caveat = " (\(EDDCore.iterateProvisionalNote))"
        lines.append(report.proven
            ? "  verdict          no test scored lower\(caveat)"
            : "  verdict          \(report.comparison.regressed) "
                + (report.comparison.regressed == 1 ? "test" : "tests") + " scored lower — not proven\(caveat)")
        if let keptCopy { lines.append("  copy kept        \(keptCopy)") }
        // Anything skipped or refused, in the same shape the other reporting commands use.
        for disclosure in report.disclosures { lines.append("  ! \(disclosure.subject): \(disclosure.reason)") }
        lines.append(report.proven
            ? "→ land it: \(landCommand)"
            : "→ nothing was changed — draft again, or apply a subset with --edits")
        return Rendering(stdout: lines.joined(separator: "\n") + "\n")
    }

    /// A name in a fixed-width column: padded when it fits, and shortened **with a marker** when it does
    /// not, so a cut name can never be mistaken for the whole one.
    static func fitted(_ text: String, to width: Int) -> String {
        guard text.count > width else { return text.padding(toLength: width, withPad: " ", startingAt: 0) }
        return String(text.prefix(width - 1)) + "…"
    }

    public func renderApply(_ result: ApplyResult, nextSteps: [String] = []) throws -> Rendering {
        switch mode {
        case .json:
            return Rendering(stdout: try SkilletJSON.encode(result) + "\n")
        case .human:
            var lines = ["apply — \(result.skill)"]
            lines.append("  draft            \(result.proposalId)")
            lines.append("  file             \(result.path)")
            let applied = zip(result.applied, result.lines).map { "\($0) (line \($1))" }
            let none = "(none)"
            lines.append(result.dryRun
                ? "  would apply      \(applied.isEmpty ? none : applied.joined(separator: ", "))"
                : "  applied          \(applied.joined(separator: ", "))")
            // Stated every time, not only when someone asks: this command stops short of the commit,
            // and a reader should never have to remember that.
            lines.append(result.dryRun
                ? "  dry run          nothing written"
                : "  committed        no — review the change and commit it yourself")
            for disclosure in result.disclosures {
                lines.append("  ! \(disclosure.subject): \(disclosure.reason)")
            }
            if !nextSteps.isEmpty { lines.append("→ next: " + nextSteps.joined(separator: " · ")) }
            return Rendering(stdout: lines.joined(separator: "\n") + "\n")
        }
    }

    /// `skillet suggest` (F41). **Report-and-point:** the summary states what happened and names the file
    /// written; the drafted edits themselves live in that file, never duplicated here.
    public func renderSuggest(_ result: SuggestResult, nextSteps: [String] = []) throws -> Rendering {
        switch mode {
        case .json:
            return Rendering(stdout: try SkilletJSON.encode(result) + "\n")
        case .human:
            return Rendering(stdout: humanSuggest(result, nextSteps: nextSteps))
        }
    }

    private func humanSuggest(_ result: SuggestResult, nextSteps: [String]) -> String {
        var lines = ["suggest — \(result.skill)"]
        lines.append("  model            \(result.model)")
        lines.append("  instructions     \(result.promptVersion)")
        lines.append("  evidence         \(result.motivation.joined(separator: ", "))")
        // A14: an empty proof list is normal and must never be silent — say what it means and what to do.
        lines.append(result.expected.isEmpty
            ? "  proves           (none — no eval is linked to this evidence yet; write one so a fix can be proven)"
            : "  proves           \(result.expected.joined(separator: ", "))")
        lines.append("  prompt size      \(result.estimatedPromptBytes) bytes")
        if result.dryRun {
            lines.append("  dry run          nothing sent, nothing written")
        } else {
            // Say what actually happened to the file. This printed `written <path>` for every outcome
            // that had a path, so a repeat run claimed it had written a file while the next line said
            // nothing had been written — and a run that saved nothing said "drafted 0 edits", which reads
            // as "the model produced nothing" when it produced edits that were simply not saved.
            // **No catch-all.** Every outcome is spelled out, so adding one stops the build here until
            // somebody says what it prints — rather than quietly reusing the "written" wording, which is
            // what the old default branch did for anything it did not recognise.
            switch result.outcome {
            case .notSaved:
                lines.append("  not saved        a different draft already holds that name")
            case .refreshed:
                lines.append("  edits            \(result.edits)")
                if let path = result.path { lines.append("  refreshed        \(path) — its list of evals was out of date") }
            case .unchanged:
                lines.append("  edits            \(result.edits)")
                if let path = result.path { lines.append("  already there    \(path) — nothing was rewritten") }
            case .written, .previewed:
                lines.append("  drafted          \(result.edits) edit\(result.edits == 1 ? "" : "s")")
                if let path = result.path { lines.append("  written          \(path)") }
            }
        }
        for disclosure in result.disclosures {
            lines.append("  ! \(disclosure.subject): \(disclosure.reason)")
        }
        for step in nextSteps { lines.append("→ next: \(step)") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A generic aligned table for plumbing/listing output (e.g. `harness info`). Column widths come
    /// from the widest cell; the last column is left unpadded to avoid trailing whitespace.
    public func renderTable(_ headers: [String], _ rows: [[String]]) -> Rendering {
        let columns = headers.count
        var widths = headers.map(\.count)
        for row in rows {
            for index in 0..<min(columns, row.count) {
                widths[index] = max(widths[index], row[index].count)
            }
        }
        func line(_ cells: [String]) -> String {
            (0..<columns).map { index -> String in
                let cell = index < cells.count ? cells[index] : ""
                return index == columns - 1 ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }
        var out = bold(line(headers)) + "\n"
        for row in rows { out += line(row) + "\n" }
        return Rendering(stdout: out)
    }

    // MARK: - Human rendering

    private func bold(_ text: String) -> String {
        color.enabled ? "\u{1B}[1m\(text)\u{1B}[0m" : text
    }

    private func red(_ text: String) -> String {
        color.enabled ? "\u{1B}[31m\(text)\u{1B}[0m" : text
    }

    private func humanRoot(_ info: RootInfo) -> String {
        var out = bold("🍳 skillet — the SKILL.md Evaluation Toolkit") + "\n\n"
        out += "The eval-driven development loop:\n"
        for verb in info.loop {
            let name = verb.name.padding(toLength: 10, withPad: " ", startingAt: 0)
            out += "  \(name)\(verb.summary)\n"
        }
        out += "\n"
        if let root = info.project.root {
            out += "Project: \(root) (via \(info.project.discoveredVia.rawValue))\n"
        } else {
            out += "Project: none found — run from a skills repo, or initialize with `skillet init`\n"
        }
        out += bold("→ next: skillet --help") + "\n"
        return out
    }

    private func humanError(_ error: EDDError) -> String {
        var out = "\(red("error:")) \(error.message)\n"
        out += "  fix: \(error.remedy)\n"
        return out
    }

    private func humanScore(_ report: ScoreReport, nextSteps: [String]) -> String {
        var out = ""
        if report.findings.isEmpty {
            out += bold("✓ score: no findings") + "\n"
        } else {
            let rows = report.findings.map { finding -> [String] in
                let location: String
                switch finding.location {
                case let .region(file, line, _, _, _, _, _): location = "\(file):\(line)"
                case let .file(file): location = file
                }
                let rank = finding.rank.map { String(Int($0)) } ?? ""
                return [finding.ruleId, finding.level.rawValue, rank, location, finding.message]
            }
            out += renderTable(["RULE", "LEVEL", "RANK", "FILE:LINE", "MESSAGE"], rows).stdout
            let errors = report.findings.filter { $0.level == .error }.count
            let warnings = report.findings.filter { $0.level == .warning }.count
            let findingCount = report.findings.count, fileCount = report.summary.filesScored
            let findingWord = findingCount == 1 ? "finding" : "findings"
            let fileWord = fileCount == 1 ? "file" : "files"
            out += "\n\(findingCount) \(findingWord) (\(errors) error · \(warnings) warning) across \(fileCount) \(fileWord)\n"
        }
        if !nextSteps.isEmpty {
            out += "\(bold("→ next:")) \(nextSteps.joined(separator: " · "))\n"
        }
        return out
    }

    private func humanInit(_ report: InitReport, nextSteps: [String]) -> String {
        var out = bold("Initialized skillet") + "\n"
        out += "  created \(report.created.count) · skipped \(report.skipped.count) · skills \(report.skills.count)\n"
        for path in report.created { out += "  + \(path)\n" }
        if !nextSteps.isEmpty {
            out += "\n\(bold("→ next:")) \(nextSteps.joined(separator: " · "))\n"
        }
        return out
    }

    private func humanLint(_ report: LintReport, nextSteps: [String]) -> String {
        var out = ""
        if report.diagnostics.isEmpty {
            out += bold("✓ lint: no findings") + "\n"
        } else {
            let rows = report.diagnostics.map { [$0.id, $0.tier.rawValue, $0.skill, $0.message] }
            out += renderTable(["RULE", "TIER", "SKILL", "MESSAGE"], rows).stdout
            out += "\n"
            for diagnostic in report.diagnostics {
                out += "  \(diagnostic.id) fix: \(diagnostic.fixHint)\n"
            }
            out += "\n" + lintSummary(report) + "\n"
        }
        if !nextSteps.isEmpty {
            out += "\(bold("→ next:")) \(nextSteps.joined(separator: " · "))\n"
        }
        return out
    }

    private func lintSummary(_ report: LintReport) -> String {
        let errors = "\(report.errors) error\(report.errors == 1 ? "" : "s")"
        let warnings = "\(report.warnings) warning\(report.warnings == 1 ? "" : "s")"
        return "\(report.errors > 0 ? red(errors) : errors) · \(warnings)"
    }

    private func humanDoctor(_ report: DoctorReport, nextSteps: [String]) -> String {
        let failures = report.rows.filter { $0.status == .failure }.count
        let warnings = report.rows.filter { $0.status == .warning }.count
        var out = report.healthy
            ? bold("✓ doctor: ready" + (warnings > 0 ? " (\(warnings) warning\(warnings == 1 ? "" : "s"))" : "")) + "\n"
            : red("✗ doctor: \(failures) failure\(failures == 1 ? "" : "s")") + "\n"
        for row in report.rows {
            let mark: String
            switch row.status {
            case .pass: mark = "✓"
            case .warning: mark = "!"
            case .failure: mark = red("✗")
            }
            let subject = row.subject.map { " \($0):" } ?? ""
            out += "  \(mark) \(row.check)\(subject) \(row.message)\n"
            if let remedy = row.remedy {
                out += "      fix: \(remedy)\n"
            }
        }
        if !nextSteps.isEmpty {
            out += "\(bold("→ next:")) \(nextSteps.joined(separator: " · "))\n"
        }
        return out
    }

    private func humanTriage(_ report: TriageReport, nextSteps: [String]) -> String {
        var out = ""
        if report.skills.isEmpty {
            out += "no skills found — nothing to triage\n"
        }
        for skillReport in report.skills {
            out += bold("triage — \(skillReport.skill)") + "\n"
            if skillReport.totalRecordings == 0 {
                // Distinguish "nothing captured yet" from "candidates found but none usable": the
                // latter must surface every skipped input (the dead-letter channel — round 5). A
                // bare "no recordings" would hide an unreadable sessions dir or all-corrupt bundles.
                if skillReport.disclosures.isEmpty {
                    out += "  no recordings yet — capture a session to give triage a corpus\n"
                } else {
                    out += "  no usable recordings — every candidate was skipped:\n"
                    for disclosure in skillReport.disclosures {
                        out += "  ! \(disclosure.subject): \(disclosure.reason)\n"
                    }
                }
                continue
            }
            // Corpus-health notes first (staleness D1, coverage A7) — before any cluster claims.
            if skillReport.staleRecordings > 0 {
                out += "  ! \(skillReport.staleRecordings) of \(skillReport.totalRecordings) recording(s) scored by a different skillet version — re-capture (or a future --rescore) to refresh\n"
            }
            if skillReport.unreadableHits > 0 {
                out += "  note: \(skillReport.unreadableHits) unreadable-file disclosure(s) in the cached scores (coverage, not a failure cluster)\n"
            }
            if skillReport.clusters.isEmpty {
                out += "  ✓ no failure clusters — cached scorer findings are clean\n"
            } else {
                let rows = skillReport.clusters.map { cluster -> [String] in
                    let status: String
                    // The FILE column reads the finalized outcome straight from `fileStatus` (round 15):
                    // no inference, and a write error is never mislabeled "a file exists".
                    let path = "findings/\(cluster.findingId).md"
                    switch cluster.fileStatus {
                    case "new": status = "new: \(path)"                                   // --dry-run preview (would write)
                    case "written": status = "written: \(path)"
                    case "blocked-exists": status = "blocked — \(path) already exists (see note)"
                    case "write-failed": status = "write failed — \(path) (see note)"
                    case "closed-still-firing": status = "closed — still firing; reopen if it's back"
                    default: status = "exists (\(cluster.state?.rawValue ?? "?"))"
                    }
                    return [cluster.cluster, "\(cluster.hits)",
                            "\(cluster.recordings.count)/\(cluster.totalRecordings)",
                            cluster.worstLevel, "\(cluster.lever.rawValue) (hypothesis)",
                            cluster.confidence.rawValue, status]
                }
                out += renderTable(["CLUSTER", "HITS", "RECS", "WORST", "LEVER", "CONF", "FILE"], rows).stdout
                for cluster in skillReport.clusters where !cluster.linkedFriction.isEmpty {
                    out += "  ↳ \(cluster.cluster) shares session(s) with friction: \(cluster.linkedFriction.joined(separator: ", "))\n"
                }
                out += "  routing is a hypothesis, not a verdict — edit a finding's `lever` to re-route\n"
            }
            for disclosure in skillReport.disclosures {
                out += "  ! \(disclosure.subject): \(disclosure.reason)\n"
            }
            if !report.dryRun, !skillReport.written.isEmpty {
                out += "  wrote \(skillReport.written.count) finding file(s): \(skillReport.written.joined(separator: ", "))\n"
            }
        }
        // Run-level, once (round 4: inside the loop it repeated per skill on multi-skill runs —
        // dry-run is a property of the invocation, not of a skill).
        if report.dryRun {
            out += "(dry-run: no files written)\n"
        }
        if !nextSteps.isEmpty {
            out += "\(bold("→ next:")) \(nextSteps.joined(separator: " · "))\n"
        }
        return out
    }

    private func humanRun(_ report: RunReport, nextSteps: [String]) -> String {
        var out = ""
        // Behavioral section — skipped entirely on a trigger-only run (§6.1: axes report separately).
        if !(report.evals.isEmpty && report.trigger != nil) {
            let allPass = !report.evals.isEmpty && report.passed == report.evals.count
            // pass^k is only a number at observed k ≥ 2; below that, consistency is unmeasurable (§4
            // vocab). pass^1 (the mean trial pass rate, §14-11) is well-defined at any k, so it shows.
            let headline = report.measurable
                ? String(format: "pass^k %.2f (k=%d) · pass^1 %.2f", locale: Self.neutralNumbers, report.passK, report.observedK, report.passOne)
                : String(format: "consistency unmeasurable (k=%d) · pass^1 %.2f", locale: Self.neutralNumbers, report.observedK, report.passOne)
            out += (allPass ? bold("✓ run: \(report.skill) — behavior — \(headline)") : red("✗ run: \(report.skill) — behavior — \(headline)")) + "\n"
            if let ab = report.ab {
                // F15: both arms side by side in the STATUS passes/trials idiom, plus the paired Δ
                // per eval — flips and magnitudes read together. An unmeasured pair (no measured
                // trials in an arm) prints "—"/"n/a", never a fabricated status or ±1.00.
                let rows = ab.perEval.map { row in
                    [row.id,
                     "\(row.withStatus.rawValue) \(row.withPasses)/\(row.withRecorded)",
                     row.baselineRecorded == 0
                         ? "— 0/0"
                         : "\(row.baselineStatus.rawValue) \(row.baselinePasses)/\(row.baselineRecorded)",
                     row.delta.map { String(format: "%+.2f", locale: Self.neutralNumbers, $0) } ?? "n/a"]
                }
                out += renderTable(["EVAL", "WITH", "BASELINE", "Δ"], rows).stdout
                out += "\n\(report.passed) passed · \(report.flaky) flaky · \(report.failed) failed · observed k=\(report.observedK) (with-skill arm)\n"
                out += abFooter(ab)
            } else {
                let rows = report.evals.map { [$0.id, $0.status.rawValue, "\($0.passes)/\($0.recorded)"] }
                out += renderTable(["EVAL", "STATUS", "PASSES"], rows).stdout
                out += "\n\(report.passed) passed · \(report.flaky) flaky · \(report.failed) failed · observed k=\(report.observedK)\n"
            }
        }
        // Trigger section (F14) — the description axis, reported separately (§6.1).
        if let trigger = report.trigger {
            let allPass = !trigger.evals.isEmpty && trigger.passed == trigger.evals.count
            let headline = trigger.measurable
                ? String(format: "pass^k %.2f (k=%d) · pass^1 %.2f", locale: Self.neutralNumbers, trigger.passK, trigger.observedK, trigger.passOne)
                : String(format: "consistency unmeasurable (k=%d) · pass^1 %.2f", locale: Self.neutralNumbers, trigger.observedK, trigger.passOne)
            out += (allPass ? bold("✓ run: \(report.skill) — trigger — \(headline)") : red("✗ run: \(report.skill) — trigger — \(headline)")) + "\n"
            let rows = trigger.evals.map { [$0.id, $0.status.rawValue, "\($0.passes)/\($0.recorded)"] }
            out += renderTable(["CASE", "STATUS", "PASSES"], rows).stdout
            out += "\n\(trigger.passed) passed · \(trigger.flaky) flaky · \(trigger.failed) failed · observed k=\(trigger.observedK)\n"
        }
        if !nextSteps.isEmpty {
            out += "\(bold("→ next:")) \(nextSteps.joined(separator: " · "))\n"
        }
        return out
    }

    /// The paired-comparison footer (F15): the suite verdict as a paired mean Δ ± SE (or an honest
    /// "too few" / "unmeasured" — never invented certainty), the flip tally over measured pairs,
    /// the time Δ, and the loud hygiene lines (pollution; unmeasured pairs; flaky-in-either-arm
    /// evals whose Δ is untrusted).
    private func abFooter(_ ab: ABComparison) -> String {
        var out = ""
        let measured = ab.perEval.count - ab.unmeasuredEvalIds.count
        let effect: String
        if measured == 0 {
            effect = "unmeasured — no eval has measured trials in both arms"
        } else {
            effect = ab.pairedSE.map { String(format: "%+.2f ± %.2f", locale: Self.neutralNumbers, ab.pairedMeanDelta, $0) }
                ?? String(format: "%+.2f (too few evals for uncertainty)", locale: Self.neutralNumbers, ab.pairedMeanDelta)
        }
        let time = ab.timeDeltaSeconds.map { String(format: "%+.1fs", locale: Self.neutralNumbers, $0) } ?? "—"
        // **A dash means nothing counted, not "we do not do that yet".** This was written as a dash
        // whatever had happened, while the saved file beside it recorded a real figure — a number the
        // record promised and no reader could get. It now shows what was measured, and still shows a dash
        // when one of the two sides counted nothing, which is when there is no difference to state.
        let tokens = ab.tokenDeltaPerAttempt.map { String(format: "%+.0f", locale: Self.neutralNumbers, $0) } ?? "—"
        out += "skill effect (paired Δ pass rate): \(effect) · flips \(ab.flipsUp)↑ \(ab.flipsDown)↓ of \(measured) · time Δ \(time) · tokens Δ \(tokens)\n"
        if ab.polluted > 0 {
            out += red("⚠ \(ab.polluted) baseline trial(s) polluted — a skill fired in the no-skill arm; excluded from every count (isolation failed on this machine)") + "\n"
        }
        if !ab.unmeasuredEvalIds.isEmpty {
            out += "\(ab.unmeasuredEvalIds.count) eval(s) without measured trials in both arms — no Δ, no flip: \(ab.unmeasuredEvalIds.joined(separator: ", "))\n"
        }
        if !ab.untrustedEvalIds.isEmpty {
            out += "\(ab.untrustedEvalIds.count) eval(s) flaky in an arm — Δ untrusted until stabilized: \(ab.untrustedEvalIds.joined(separator: ", "))\n"
        }
        return out
    }
}
