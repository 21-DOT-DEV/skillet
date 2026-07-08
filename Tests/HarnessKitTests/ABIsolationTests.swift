import Testing
import Foundation
import EDDCore
import TraceKit
@testable import HarnessKit

@Suite("A/B baseline isolation (F15)")
struct ABIsolationTests {
    private func adapter(help: String, helpExit: Int32 = 0) -> ClaudeCodeAdapter {
        ClaudeCodeAdapter(
            configPath: "/cfg/claude",
            launcher: FakeLauncher(output: ProcessOutput(stdout: help, stderr: "", exitCode: helpExit)),
            resolver: BinaryResolver(probe: FakeExecutableProbe(), environment: [:]),
            environment: [:]
        )
    }

    @Test("The baseline arm appends --disable-slash-commands; the with-arm invocation is unchanged")
    func isolatedArgShape() {
        let withArm = ClaudeCodeAdapter.runArguments(prompt: "p")
        let isolated = ClaudeCodeAdapter.runArguments(prompt: "p", isolated: true)
        #expect(!withArm.contains("--disable-slash-commands"))
        #expect(isolated.last == "--disable-slash-commands")
        #expect(Array(isolated.dropLast()) == withArm)   // the switch is strictly additive
    }

    @Test("verifyBaselineIsolation: a --help advertising the switch passes for $0")
    func isolationSupported() async throws {
        try await adapter(help: "Usage: claude [options]\n  --disable-slash-commands  Disable all skills and commands\n")
            .verifyBaselineIsolation()
    }

    @Test("verifyBaselineIsolation: a binary without the switch is refused with the F15 error (exit 3)")
    func isolationUnsupported() async {
        await #expect(throws: EDDError.baselineNotIsolable(
            harness: "claude-code",
            reason: "the resolved binary does not advertise --disable-slash-commands, so ambient personal skills cannot be provably excluded from the baseline arm"
        )) {
            try await adapter(help: "Usage: claude [options]\n  --verbose\n").verifyBaselineIsolation()
        }
    }

    @Test("verifyBaselineIsolation: a failing --help is refused, never assumed")
    func helpFails() async {
        await #expect(throws: EDDError.self) {
            try await adapter(help: "", helpExit: 1).verifyBaselineIsolation()
        }
    }

    @Test("ReplayAdapter is arm-aware: .none serves a skill-free trace; the with-arm still fires demo")
    func replayArmAware() async throws {
        let replay = ReplayAdapter()
        let ws = Workspace(root: FileManager.default.temporaryDirectory)
        let baseline = try replay.parseTrace(try await replay.run(TaskSpec(query: "q"), in: ws, skills: SkillSet.none))
        #expect(baseline.skillInvocations.isEmpty)
        let with = try replay.parseTrace(try await replay.run(TaskSpec(query: "q"), in: ws, skills: .only(load: [])))
        #expect(with.skillInvocations.map(\.skill) == ["demo"])
    }

    @Test("An adapter without the capability refuses baseline isolation loudly (declare-cannot, §9.2)")
    func defaultRefuses() async {
        struct Bare: HarnessAdapter {
            let id: HarnessID = "bare"
            let capabilities: HarnessCapabilities = [.runTask]
            func probe(strict: Bool) async throws -> HarnessInfo { HarnessInfo(id: id, version: "x", authenticated: true, available: true) }
        }
        await #expect(throws: HarnessError.notSupported(capability: "baseline_isolation")) {
            try await Bare().verifyBaselineIsolation()
        }
    }
}
