import ArgumentParser
import Foundation
import EDDCore
import TraceKit
import HarnessKit
import RenderKit

/// `skillet harness` — inspect the harness adapters behind the seam (F5). `info`/`list` are
/// informational ($0); claude-code's live `run` lands in F7. `info` probes the real adapter (F6).
struct HarnessCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "harness",
        abstract: "Inspect harness adapters.",
        subcommands: [HarnessListCommand.self, HarnessInfoCommand.self],
        defaultSubcommand: HarnessInfoCommand.self
    )
}

struct HarnessListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List registered harness adapters and their capabilities."
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            let report = await HarnessInfoReport.build(from: try configuredRegistry(options: options))
            if options.json {
                Console.emit(Rendering(stdout: try SkilletJSON.encode(report) + "\n"))
            } else {
                let rows = report.adapters.map { [$0.id, $0.capabilities.joined(separator: ", ")] }
                Console.emit(renderer.renderTable(["ADAPTER", "CAPABILITIES"], rows))
            }
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }
}

struct HarnessInfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show harness adapters, their capability matrix, and probe status."
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Limit to one adapter id (e.g. claude-code).")
    var id: String?

    func run() async throws {
        let renderer = options.makeRenderer()
        do {
            let registry = try configuredRegistry(options: options)
            if let id, registry.adapter(id: HarnessID(id)) == nil {
                throw EDDError.usage(
                    message: "unknown harness id: \(id)",
                    remedy: "run `skillet harness list` to see registered adapters"
                )
            }
            let chosen = id.map { wanted in
                HarnessRegistry(adapters: registry.adapters.filter { $0.id.rawValue == wanted })
            } ?? registry
            let report = await HarnessInfoReport.build(from: chosen)
            if options.json {
                Console.emit(Rendering(stdout: try SkilletJSON.encode(report) + "\n"))
            } else {
                let rows = report.adapters.map { adapter -> [String] in
                    var status = adapter.available
                        ? "available (\(adapter.version ?? "?"))"
                        : (adapter.detail ?? "unavailable")
                    for warning in adapter.warnings { status += "  ⚠️ \(warning)" }
                    return [adapter.id, adapter.capabilities.joined(separator: ", "), status]
                }
                Console.emit(renderer.renderTable(["ADAPTER", "CAPABILITIES", "STATUS"], rows))
            }
        } catch let error as EDDError {
            Console.emit(renderer.renderError(error))
            throw SilentExit(code: error.exitCode.rawValue)
        }
    }
}
