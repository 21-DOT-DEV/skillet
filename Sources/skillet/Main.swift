import ArgumentParser
import Foundation
import EDDCore
import RenderKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Thrown after a command has already rendered its own error, to carry the exit code out to `main`
/// without printing anything again.
struct SilentExit: Error {
    let code: Int32
}

/// Custom entry point so exit codes follow skillet's stable §5.4 table rather than ArgumentParser's
/// defaults: help/version → 0, any parse/usage error → 2, rendered domain errors → their code.
@main
struct SkilletMain {
    static func main() async {
        do {
            // parseAsRoot dispatches to the right command (root or a subcommand like `init`).
            var command = try SkilletCommand.parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch let silent as SilentExit {
            exit(silent.code)
        } catch let error as EDDError {
            // Defensive: commands render their own EDDErrors. An unrendered one prints plainly.
            Console.emit(Renderer(mode: .human, color: ColorPolicy(enabled: false)).renderError(error))
            exit(error.exitCode.rawValue)
        } catch {
            // ArgumentParser: help/version are "clean" exits (success); everything else is a usage error.
            let message = SkilletCommand.fullMessage(for: error)
            if SkilletCommand.exitCode(for: error) == .success {
                if !message.isEmpty { print(message) }
                exit(EDDCore.ExitCode.success.rawValue)
            } else {
                if !message.isEmpty {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                }
                exit(EDDCore.ExitCode.usage.rawValue)
            }
        }
    }
}
