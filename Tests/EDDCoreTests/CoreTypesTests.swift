import Testing
import EDDCore

@Suite("ExitCode & EDDError")
struct CoreTypesTests {
    @Test("Exit codes match the stable §5.4 table")
    func exitCodeRawValues() {
        #expect(ExitCode.success.rawValue == 0)
        #expect(ExitCode.measuredFailure.rawValue == 1)
        #expect(ExitCode.usage.rawValue == 2)
        #expect(ExitCode.environment.rawValue == 3)
        #expect(ExitCode.artifact.rawValue == 4)
        #expect(ExitCode.gate.rawValue == 5)
    }

    @Test("Errors map to the right exit code")
    func errorExitCodes() {
        #expect(EDDError.usage(message: "m", remedy: "r").exitCode == .usage)
        #expect(EDDError.directoryNotFound(path: "/x").exitCode == .environment)
        #expect(EDDError.projectNotFound(cwd: "/x").exitCode == .environment)
    }

    @Test("Errors carry a machine kind, a message, and a remedy")
    func errorFields() {
        let error = EDDError.directoryNotFound(path: "/no/such")
        #expect(error.kind == "directory_not_found")
        #expect(error.message.contains("/no/such"))
        #expect(!error.remedy.isEmpty)

        let usage = EDDError.usage(message: "bad flag", remedy: "see --help")
        #expect(usage.kind == "usage")
        #expect(usage.message == "bad flag")
        #expect(usage.remedy == "see --help")
    }
}
