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

    private func humanRun(_ report: RunReport, nextSteps: [String]) -> String {
        var out = ""
        // Behavioral section — skipped entirely on a trigger-only run (§6.1: axes report separately).
        if !(report.evals.isEmpty && report.trigger != nil) {
            let allPass = !report.evals.isEmpty && report.passed == report.evals.count
            // pass^k is only a number at observed k ≥ 2; below that, consistency is unmeasurable (§4
            // vocab). pass^1 (the mean trial pass rate, §14-11) is well-defined at any k, so it shows.
            let headline = report.measurable
                ? String(format: "pass^k %.2f (k=%d) · pass^1 %.2f", report.passK, report.observedK, report.passOne)
                : String(format: "consistency unmeasurable (k=%d) · pass^1 %.2f", report.observedK, report.passOne)
            out += (allPass ? bold("✓ run: \(report.skill) — behavior — \(headline)") : red("✗ run: \(report.skill) — behavior — \(headline)")) + "\n"
            let rows = report.evals.map { [$0.id, $0.status.rawValue, "\($0.passes)/\($0.recorded)"] }
            out += renderTable(["EVAL", "STATUS", "PASSES"], rows).stdout
            out += "\n\(report.passed) passed · \(report.flaky) flaky · \(report.failed) failed · observed k=\(report.observedK)\n"
        }
        // Trigger section (F14) — the description axis, reported separately (§6.1).
        if let trigger = report.trigger {
            let allPass = !trigger.evals.isEmpty && trigger.passed == trigger.evals.count
            let headline = trigger.measurable
                ? String(format: "pass^k %.2f (k=%d) · pass^1 %.2f", trigger.passK, trigger.observedK, trigger.passOne)
                : String(format: "consistency unmeasurable (k=%d) · pass^1 %.2f", trigger.observedK, trigger.passOne)
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
}
