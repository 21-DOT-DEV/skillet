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

/// Process-launch failures the run loop classifies (design §10). A timeout is the per-trial watchdog
/// firing — distinct from the child exiting non-zero on its own.
public enum ProcessError: Error, Sendable, Equatable {
    case timedOut(after: Duration)
}

/// The single process-launch seam (constitution VI — no `Foundation.Process`). Injectable so probe/run
/// logic is unit-tested with a fake; the real launcher is used in production and F7's env-gated smoke.
/// F7 widened the contract: a per-trial `timeout` watchdog, a sandbox `workingDirectory`, and an
/// optional `environment` overlay (each `nil` ⇒ inherit / no limit).
public protocol ProcessLauncher: Sendable {
    func run(
        _ executable: String,
        _ arguments: [String],
        workingDirectory: String?,
        timeout: Duration?,
        environment: [String: String]?,
        outputLimitBytes: Int?
    ) async throws -> ProcessOutput

    /// Pipe `input` to the child's stdin — F26/F32 feed `betterleaks` this way so raw session text
    /// never touches disk (spike-verified: swift-subprocess `input: .data(...)`). A default impl below
    /// forwards to the no-input `run` (ignoring `input`), so existing conformers/fakes need no change;
    /// only `SubprocessLauncher` overrides it to actually write stdin.
    func run(
        _ executable: String,
        _ arguments: [String],
        input: Data?,
        workingDirectory: String?,
        timeout: Duration?,
        environment: [String: String]?,
        outputLimitBytes: Int?
    ) async throws -> ProcessOutput
}

public extension ProcessLauncher {
    /// Default: ignore `input`, forward to the no-input `run` (for launchers/fakes without stdin support).
    func run(
        _ executable: String, _ arguments: [String], input: Data?,
        workingDirectory: String?, timeout: Duration?, environment: [String: String]?, outputLimitBytes: Int?
    ) async throws -> ProcessOutput {
        try await run(executable, arguments, workingDirectory: workingDirectory, timeout: timeout,
                      environment: environment, outputLimitBytes: outputLimitBytes)
    }

    /// Convenience for no-frills call sites (e.g. probe's `--version`): inherit cwd + env, no watchdog,
    /// default output limit.
    func run(_ executable: String, _ arguments: [String]) async throws -> ProcessOutput {
        try await run(executable, arguments, workingDirectory: nil, timeout: nil, environment: nil, outputLimitBytes: nil)
    }
}

/// The real launcher, over `swift-subprocess`.
public struct SubprocessLauncher: ProcessLauncher {
    /// Built-in stdout/stderr capture cap when a call passes `outputLimitBytes: nil` (e.g. probe). A
    /// caller (a paid trial) overrides via `runs.max_output_bytes`. Bounded so a runaway child can't
    /// exhaust memory; generous so a normal `stream-json` session isn't truncated into a false failure.
    static let defaultOutputLimit = 64 << 20

    public init() {}

    public func run(
        _ executable: String,
        _ arguments: [String],
        workingDirectory: String?,
        timeout: Duration?,
        environment: [String: String]?,
        outputLimitBytes: Int?
    ) async throws -> ProcessOutput {
        try await run(executable, arguments, input: nil, workingDirectory: workingDirectory,
                      timeout: timeout, environment: environment, outputLimitBytes: outputLimitBytes)
    }

    public func run(
        _ executable: String,
        _ arguments: [String],
        input: Data?,
        workingDirectory: String?,
        timeout: Duration?,
        environment: [String: String]?,
        outputLimitBytes: Int?
    ) async throws -> ProcessOutput {
        let limit = outputLimitBytes ?? Self.defaultOutputLimit
        // No watchdog → run directly.
        guard let timeout else {
            return try await Self.runOnce(executable, arguments, input, workingDirectory, environment, limit)
        }
        // Watchdog: race the child against a sleeper. Whichever finishes first wins; exiting the group
        // cancels the loser — cancelling the child task makes swift-subprocess terminate the process.
        return try await withThrowingTaskGroup(of: ProcessOutput?.self) { group in
            group.addTask { try await Self.runOnce(executable, arguments, input, workingDirectory, environment, limit) }
            group.addTask { try await Task.sleep(for: timeout); return nil }   // nil sentinel = timed out
            defer { group.cancelAll() }
            let first = try await group.next() ?? nil
            if let output = first { return output }
            throw ProcessError.timedOut(after: timeout)
        }
    }

    /// One un-timed subprocess invocation.
    private static func runOnce(
        _ executable: String,
        _ arguments: [String],
        _ input: Data?,
        _ workingDirectory: String?,
        _ environment: [String: String]?,
        _ outputLimit: Int
    ) async throws -> ProcessOutput {
        // `nil` inherits the parent environment; a supplied overlay layers on top of it (so PATH etc.
        // survive) rather than replacing it.
        let env: Environment = environment.map { overlay in
            .inherit.updating(Dictionary(uniqueKeysWithValues: overlay.map {
                (Environment.Key(stringLiteral: $0.key), Optional($0.value))
            }))
        } ?? .inherit
        // A bare name (no `/`) resolves via PATH (`.name`); an absolute/relative path is used directly
        // (`.path`). The seam is documented as `executable: String` (a name OR a path), and
        // `SKILLET_*_BIN`/config may be a bare name (`betterleaks`, `git`, `claude`) — treating everything
        // as a path would fail to exec those even when PATH has them.
        let exe: Executable = executable.contains("/") ? .path(FilePath(executable)) : .name(executable)
        let args = Arguments(arguments)
        let cwd = workingDirectory.map { FilePath($0) }
        // Branch on stdin: `.data(...)` pipes the buffer to the child (spike-verified with betterleaks);
        // no input keeps the default (no stdin). Both collect stdout/stderr as bounded strings.
        if let input {
            let result = try await Subprocess.run(exe, arguments: args, environment: env, workingDirectory: cwd,
                                                  input: .data(input),
                                                  output: .string(limit: outputLimit), error: .string(limit: outputLimit))
            return Self.output(result.terminationStatus, result.standardOutput, result.standardError)
        } else {
            let result = try await Subprocess.run(exe, arguments: args, environment: env, workingDirectory: cwd,
                                                  output: .string(limit: outputLimit), error: .string(limit: outputLimit))
            return Self.output(result.terminationStatus, result.standardOutput, result.standardError)
        }
    }

    private static func output(_ status: TerminationStatus, _ stdout: String?, _ stderr: String?) -> ProcessOutput {
        let exitCode: Int32
        if case .exited(let code) = status { exitCode = code } else { exitCode = -1 }
        return ProcessOutput(stdout: stdout ?? "", stderr: stderr ?? "", exitCode: exitCode)
    }
}
