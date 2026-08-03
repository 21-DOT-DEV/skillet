import Foundation
import HarnessKit
import JudgeKit

/// The real ``JudgeRunner`` — lives in RunKit so JudgeKit stays decoupled from HarnessKit. It shells
/// the resolved `claude` CLI one-shot as the judge model, through HarnessKit's ``ProcessLauncher`` (the
/// same sanctioned launcher the harness adapter uses; the executable resolves the binary once and
/// injects the path into both). Exercised live only by F7's env-gated smoke; unit-tested behind a fake
/// launcher.
public struct ClaudeCLIJudgeRunner: JudgeRunner {
    let binaryPath: String
    let launcher: any ProcessLauncher
    let timeout: Duration
    let outputLimitBytes: Int?

    /// `outputLimitBytes: nil` keeps the launcher's generous default, which is right for a grader: its
    /// reply is a short verdict. **A caller whose reply is then written to a file must pass its own
    /// limit** — drafting inherited this `nil` and could therefore emit far more than it was able to
    /// read back afterwards, which is how it came to write files it then called unreadable.
    public init(binaryPath: String, launcher: any ProcessLauncher = SubprocessLauncher(),
                timeout: Duration = .seconds(120), outputLimitBytes: Int? = nil) {
        self.binaryPath = binaryPath
        self.launcher = launcher
        self.timeout = timeout
        self.outputLimitBytes = outputLimitBytes
    }

    public func ask(prompt: String, model: String) async throws -> String {
        let output = try await launcher.run(
            binaryPath,
            ["-p", prompt, "--model", model, "--output-format", "text"],
            workingDirectory: nil,
            timeout: timeout,
            environment: nil,
            outputLimitBytes: outputLimitBytes   // nil = the launcher default (fine for a short verdict)
        )
        // A non-zero judge exit is an infrastructure failure, not a FAIL verdict — surface it so the
        // run loop marks the trial ungraded rather than parsing diagnostic output as a criterion FAIL.
        guard output.exitCode == 0 else {
            throw JudgeRunnerError.failed(exitCode: output.exitCode, stderr: output.stderr)
        }
        return output.stdout
    }
}
