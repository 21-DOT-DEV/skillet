import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// The captured result of one process invocation.
public struct ProcessOutput: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32
    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// The single process-launch seam (constitution VI — no `Foundation.Process`). Injectable so `probe()`
/// logic is unit-tested with a fake; the real launcher is used in production and F7's env-gated smoke.
public protocol ProcessLauncher: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> ProcessOutput
}

/// The real launcher, over `swift-subprocess`.
public struct SubprocessLauncher: ProcessLauncher {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) async throws -> ProcessOutput {
        let result = try await Subprocess.run(
            .path(FilePath(executable)),
            arguments: .init(arguments),
            output: .string(limit: 1 << 20),
            error: .string(limit: 1 << 20)
        )
        let exitCode: Int32
        if case .exited(let code) = result.terminationStatus {
            exitCode = code
        } else {
            exitCode = -1
        }
        return ProcessOutput(stdout: result.standardOutput ?? "", stderr: result.standardError ?? "", exitCode: exitCode)
    }
}
