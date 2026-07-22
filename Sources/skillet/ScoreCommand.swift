import ArgumentParser
import Foundation
import EDDCore
import ProjectKit
import RenderKit
import ScoreKit

/// `skillet score <path>` — free, model-free deterministic scorers over produced text, emitting SARIF
/// 2.1.0 findings (design §6.2, F17). A **reporter, not a gate**: exit 0 even when scorers fire (the
/// signal feeds triage/next; it does not fail a build, unlike `lint`). No model, no network.
struct ScoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "score",
        abstract: "Free deterministic scorers over produced text → SARIF findings.",
        discussion: """
        Runs deterministic, model-free checks (AI-slop vocabulary, marketing puffery, em-dash over-use, \
        rule-of-three, knowledge-cutoff mentions) over the text files under <path> and emits standard \
        findings JSON (SARIF 2.1.0). No model, no network. A reporter, not a gate — exit 0 even with \
        findings. The human table is the default; scripts opt in:
            skillet score . --format sarif > out.sarif
        Configure folder skips and vocabulary exemptions under `scorers:` in skillet.yaml.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "File or directory of produced text to score.")
    var path: String

    @Option(name: .long, help: "Output format: tty (default), json, or sarif.")
    var format: ScoreFormat?

    enum ScoreFormat: String, ExpressibleByArgument, CaseIterable { case tty, json, sarif }

    func run() async throws {
        // Resolve the output surface up front (R8 C2: an explicit `--format` wins; else `--json` ⇒ json;
        // else tty) so **errors follow it too** — a machine format (`json`/`sarif`) renders errors as the
        // `skillet.error/1` JSON payload on stderr, not a human line, even when `--format json` is used
        // without the global `--json`.
        let fmt = format ?? (options.json ? .json : .tty)
        let errorRenderer = Renderer(mode: fmt == .tty ? .human : .json, color: options.makeRenderer().color)
        do {
            let url = URL(fileURLWithPath: path)
            // `isReadableFile` is false for a missing *or* unreadable path — both are exit-3 environment
            // errors (not a silent empty/S000 result).
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw EDDError.pathNotFound(path: path)
            }

            // Config: repo skillet.yaml + built-in defaults (no user layer until F24); a corrupt config
            // is an artifact error (exit 4). Outside a repo → defaults.
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
            let scorers = (try loadConfig(options: options, context: context))?.scorers ?? SkilletConfig.Scorers()

            // Progress note (clig.dev): a one-line status on stderr for the human table only, never when
            // piped or emitting machine output.
            let showProgress = fmt == .tty && Console.isStdoutTTY()
            let output = ScoreRunner(toolVersion: SkilletVersion.current).run(path: url, config: scorers) { count in
                guard showProgress else { return }
                let noun = count == 1 ? "file" : "files"
                FileHandle.standardError.write(Data("scoring \(count) \(noun)…\n".utf8))
            }

            switch fmt {
            case .sarif:
                Console.emit(Rendering(stdout: try output.sarif.jsonString() + "\n"))       // bypasses Renderer
            case .json:
                Console.emit(Rendering(stdout: try SkilletJSON.encode(output.report) + "\n"))
            case .tty:
                let renderer = Renderer(mode: .human, color: errorRenderer.color)
                Console.emit(try renderer.renderScore(output.report, nextSteps: Self.nextSteps()))
            }
            // Reporter: no non-zero exit on findings.
        } catch let error as EDDError {
            Console.emit(errorRenderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }

    /// Suggest the next loop steps that exist today (registration-filtered, like `LintCommand`).
    /// `triage` joins the list with F33 — score's findings feed it (design §6.1: score "feeds triage/§8").
    static func nextSteps() -> [String] {
        let registered = Set(SkilletCommand.configuration.subcommands.compactMap { $0.configuration.commandName })
        let available = ["lint", "run", "triage"].filter { registered.contains($0) }.map { "skillet \($0)" }
        return available.isEmpty ? ["skillet --help"] : available
    }
}
