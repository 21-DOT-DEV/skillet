import ArgumentParser
import Foundation
import RenderKit

// ColorChoice is RenderKit's; the executable owns its CLI parsing conformance.
// (Same-package conformance, so no @retroactive needed.)
extension ColorChoice: ExpressibleByArgument {}

/// The global flags shared by every skillet command (design §5.3). F1 wires the substrate-relevant
/// subset; spend/action flags (`--yes`, `--dry-run`, `--harness`, `--runs`) arrive with their commands.
struct GlobalOptions: ParsableArguments {
    @Option(name: .customShort("C"), help: "Operate as if started in <dir>.")
    var directory: String?

    @Flag(name: .long, help: "Emit machine-readable JSON on stdout.")
    var json = false

    @Option(name: .long, help: "Colorize output: auto, always, or never.")
    var color: ColorChoice = .auto

    @Flag(name: [.short, .long], help: "Increase verbosity.")
    var verbose = false

    @Flag(name: [.short, .long], help: "Quieter output.")
    var quiet = false

    @Option(name: .long, help: "Explicit config file path.")
    var config: String?

    var outputMode: OutputMode { json ? .json : .human }

    /// Build the renderer for this invocation, resolving color from the flag, `NO_COLOR`, and the TTY.
    func makeRenderer() -> Renderer {
        let policy = ColorPolicy.resolve(
            choice: color,
            noColorEnv: ProcessInfo.processInfo.environment["NO_COLOR"] != nil,
            isTTY: Console.isStdoutTTY()
        )
        return Renderer(mode: outputMode, color: policy)
    }
}
