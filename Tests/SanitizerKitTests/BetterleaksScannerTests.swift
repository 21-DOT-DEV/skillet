import Testing
import Foundation
import HarnessKit
@testable import SanitizerKit

/// Canned-output launcher for parse/error paths (no real betterleaks).
private struct FixedLauncher: ProcessLauncher {
    var stdout: String = "[]"
    var exitCode: Int32 = 0
    var throwOnRun: Bool = false
    func run(_ e: String, _ a: [String], workingDirectory: String?, timeout: Duration?, environment: [String: String]?, outputLimitBytes: Int?) async throws -> ProcessOutput {
        try await run(e, a, input: nil, workingDirectory: workingDirectory, timeout: timeout, environment: environment, outputLimitBytes: outputLimitBytes)
    }
    func run(_ e: String, _ a: [String], input: Data?, workingDirectory: String?, timeout: Duration?, environment: [String: String]?, outputLimitBytes: Int?) async throws -> ProcessOutput {
        if throwOnRun { throw ProcessError.timedOut(after: .seconds(1)) }
        return ProcessOutput(stdout: stdout, stderr: "", exitCode: exitCode)
    }
}

/// Records the args + piped stdin so we can assert the exact betterleaks invocation.
private actor RecordingLauncher: ProcessLauncher {
    private(set) var arguments: [String] = []
    private(set) var input: Data?
    func run(_ e: String, _ a: [String], workingDirectory: String?, timeout: Duration?, environment: [String: String]?, outputLimitBytes: Int?) async throws -> ProcessOutput {
        try await run(e, a, input: nil, workingDirectory: workingDirectory, timeout: timeout, environment: environment, outputLimitBytes: outputLimitBytes)
    }
    func run(_ e: String, _ a: [String], input: Data?, workingDirectory: String?, timeout: Duration?, environment: [String: String]?, outputLimitBytes: Int?) async throws -> ProcessOutput {
        arguments = a
        self.input = input
        return ProcessOutput(stdout: "[]", stderr: "", exitCode: 0)
    }
}

@Suite("BetterleaksScanner")
struct BetterleaksScannerTests {
    private func scanner(_ launcher: any ProcessLauncher) -> BetterleaksScanner {
        BetterleaksScanner(binaryPath: "/opt/betterleaks", launcher: launcher)
    }

    @Test("Parses findings from betterleaks JSON")
    func parsesFindings() async throws {
        let s = scanner(FixedLauncher(stdout: FindingTests.realJSON, exitCode: 1))   // exit 1 = leaks found
        let findings = try await s.scan([ScanInput(path: "transcript.md", text: "x")])
        #expect(findings.count == 1)
        #expect(findings.first?.secret == "ghp_skilletSyntheticCanaryDoNotUse123456")
    }

    @Test("Clean scan ([] , exit 0) → no findings")
    func cleanIsEmpty() async throws {
        let findings = try await scanner(FixedLauncher(stdout: "[]", exitCode: 0)).scan([ScanInput(path: "p", text: "x")])
        #expect(findings.isEmpty)
    }

    @Test("Unparseable output → scannerUnparseable (fail closed, never 'clean')")
    func unparseableThrows() async {
        await #expect(throws: SanitizerError.self) {
            _ = try await scanner(FixedLauncher(stdout: "not json", exitCode: 1)).scan([ScanInput(path: "p", text: "x")])
        }
    }

    @Test("Empty output with non-zero exit → scannerUnparseable (fail closed)")
    func emptyNonZeroThrows() async {
        await #expect(throws: SanitizerError.self) {
            _ = try await scanner(FixedLauncher(stdout: "", exitCode: 2)).scan([ScanInput(path: "p", text: "x")])
        }
    }

    @Test("Empty stdout with exit 0 → fail closed (a real scan emits []; empty ≠ clean — the /usr/bin/true bypass)")
    func emptyStdoutExit0FailsClosed() async {
        await #expect(throws: SanitizerError.self) {   // /usr/bin/true: exit 0, no output — must NOT read as clean
            _ = try await scanner(FixedLauncher(stdout: "", exitCode: 0)).scan([ScanInput(path: "p", text: "x")])
        }
    }

    @Test("verify() passes when the scanner flags the planted canary (a real scanner)")
    func verifyPassesForRealScanner() async throws {
        let canary = "ghp_skilletSyntheticCanaryDoNotUse123456"
        let json = #"[{"RuleID":"github-pat","Secret":"\#(canary)","Match":"\#(canary)","File":"__selftest__"}]"#
        try await scanner(FixedLauncher(stdout: json, exitCode: 0)).verify()   // no throw = trusted
    }

    @Test("verify() FAILS CLOSED for a stub that returns [] for everything (echo-empty / non-scanner)")
    func verifyFailsForAlwaysCleanStub() async {
        await #expect(throws: SanitizerError.self) {
            try await scanner(FixedLauncher(stdout: "[]", exitCode: 0)).verify()
        }
    }

    @Test("Parseable `[]` with a non-zero exit → fail closed (an errored scan that prints [] is NOT 'clean')")
    func emptyArrayNonZeroThrows() async {
        // The fail-open regression (Spec 014 §R3-3): betterleaks/gitleaks reuse exit 1 for errors, so an
        // error that still emits `[]` on stdout must be REFUSED — not written as an unscrubbed (zero-
        // redaction) bundle. Contrast with `parsesFindings`: exit 1 WITH findings is a legit "leaks found".
        await #expect(throws: SanitizerError.self) {
            _ = try await scanner(FixedLauncher(stdout: "[]", exitCode: 1)).scan([ScanInput(path: "p", text: "x")])
        }
    }

    @Test("Launch failure → scannerNotFound")
    func launchFailureThrowsNotFound() async {
        await #expect(throws: SanitizerError.self) {
            _ = try await scanner(FixedLauncher(throwOnRun: true)).scan([ScanInput(path: "p", text: "x")])
        }
    }

    @Test("Invokes `stdin -f json -r -` with the path attr and pipes the text as stdin")
    func passesStdinAndPathAttr() async throws {
        let rec = RecordingLauncher()
        _ = try await BetterleaksScanner(binaryPath: "/opt/betterleaks", launcher: rec)
            .scan([ScanInput(path: "sub/dir/body.md", text: "hello stdin")])
        let args = await rec.arguments
        #expect(args.prefix(4) == ["stdin", "-f", "json", "-r"])
        #expect(args.contains("--set-attr"))
        #expect(args.contains("path=sub/dir/body.md"))
        // findings-as-success: `--exit-code 0` must be passed so a non-zero exit means a real error.
        let exitIdx = args.firstIndex(of: "--exit-code")
        #expect(exitIdx.map { $0 + 1 < args.count && args[$0 + 1] == "0" } == true)
        #expect(await rec.input == Data("hello stdin".utf8))
    }

    // LIVE: exercises the REAL betterleaks binary if it's on PATH (skips cleanly otherwise). This is the
    // env-gated smoke that bakes the spike into the suite — proves the launcher→betterleaks→parse path.
    @Test("LIVE real betterleaks finds a planted secret and reports clean input (skipped if absent)")
    func liveBetterleaks() async throws {
        guard let path = await Self.resolveBetterleaks() else { return }   // not installed → skip
        let s = BetterleaksScanner(binaryPath: path, launcher: SubprocessLauncher())
        let leak = try await s.scan([ScanInput(path: "transcript.md",
            text: "token = ghp_skilletSyntheticCanaryDoNotUse123456\n")])
        #expect(leak.contains { $0.secret == "ghp_skilletSyntheticCanaryDoNotUse123456" })
        #expect(leak.first?.file == "transcript.md")
        let clean = try await s.scan([ScanInput(path: "clean.md", text: "nothing secret here at all\n")])
        #expect(clean.isEmpty)
    }

    static func resolveBetterleaks() async -> String? {
        guard let out = try? await SubprocessLauncher().run(
            "/usr/bin/which", ["betterleaks"], workingDirectory: nil, timeout: .seconds(5), environment: nil, outputLimitBytes: nil),
              out.exitCode == 0 else { return nil }
        let p = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? nil : p
    }
}
