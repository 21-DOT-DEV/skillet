import HarnessKit

/// Shared test doubles for the resolution/probe/run suites.

struct FakeExecutableProbe: ExecutableProbe {
    var executables: Set<String> = []
    var pathLookup: [String: String] = [:]
    func isExecutable(_ path: String) -> Bool { executables.contains(path) }
    func lookInPATH(_ name: String) -> String? { pathLookup[name] }
}

/// Returns a fixed `ProcessOutput` for `--version`, and a separate one for `claude auth status` so
/// probe's two non-spending calls can be driven independently (default `auth status` = logged in).
struct FakeLauncher: ProcessLauncher {
    var output: ProcessOutput
    var authOutput: ProcessOutput? = nil
    func run(_ executable: String, _ arguments: [String], workingDirectory: String?, timeout: Duration?, environment: [String: String]?, outputLimitBytes: Int?) async throws -> ProcessOutput {
        if arguments.first == "auth" {
            return authOutput ?? ProcessOutput(stdout: #"{"loggedIn":true}"#, stderr: "", exitCode: 0)
        }
        return output
    }
}

/// Captures the last invocation so `run()` tests can assert the resolved binary, args, sandbox cwd,
/// and watchdog actually reach the launcher.
actor RecordingLauncher: ProcessLauncher {
    let output: ProcessOutput
    private(set) var executable: String?
    private(set) var arguments: [String] = []
    private(set) var workingDirectory: String?
    private(set) var timeout: Duration?
    private(set) var outputLimitBytes: Int?
    init(output: ProcessOutput) { self.output = output }
    func run(_ executable: String, _ arguments: [String], workingDirectory: String?, timeout: Duration?, environment: [String: String]?, outputLimitBytes: Int?) async throws -> ProcessOutput {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.timeout = timeout
        self.outputLimitBytes = outputLimitBytes
        return output
    }
}
