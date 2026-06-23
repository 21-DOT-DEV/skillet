import HarnessKit

/// Shared test doubles for the resolution/probe suites.

struct FakeExecutableProbe: ExecutableProbe {
    var executables: Set<String> = []
    var pathLookup: [String: String] = [:]
    func isExecutable(_ path: String) -> Bool { executables.contains(path) }
    func lookInPATH(_ name: String) -> String? { pathLookup[name] }
}

struct FakeLauncher: ProcessLauncher {
    var output: ProcessOutput
    func run(_ executable: String, _ arguments: [String]) async throws -> ProcessOutput { output }
}
