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
}
