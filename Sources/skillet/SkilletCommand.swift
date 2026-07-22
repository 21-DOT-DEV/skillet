import ArgumentParser
import Foundation
import EDDCore
import ProjectKit
import RenderKit

/// The root command. With no subcommand it explains the loop (Appendix B); `--json` emits the
/// `skillet.root/1` payload with the resolved project context. Subcommands (`init`, `doctor`, …)
/// arrive in later features.
struct SkilletCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skillet",
        abstract: "The SKILL.md Evaluation Toolkit — eval-driven development for agent skills.",
        usage: """
        skillet                  show the EDD loop overview
        skillet --json           machine-readable project context
        """,
        discussion: "Run from anywhere: skillet finds its project by walking up to skillet.yaml or a .git boundary.",
        version: SkilletVersion.current,
        subcommands: [InitCommand.self, DoctorCommand.self, LintCommand.self, ScoreCommand.self, HarnessCommand.self, RunCommand.self, CaptureCommand.self, TriageCommand.self]
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let context = try ProjectLocator().locate(dashC: options.directory, cwd: cwd)
            let info = RootInfo(
                skilletVersion: SkilletVersion.current,
                project: context,
                loop: LoopVerb.canonical
            )
            Console.emit(try renderer.renderRoot(info))
        } catch let error as EDDError {
            // Render in the user's chosen mode, then exit with the mapped code (no double-printing).
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }
}
