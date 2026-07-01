import Testing
import Foundation
import EDDCore

@Suite("Run + judge config")
struct RunConfigTests {
    // Decoded via JSON (EDDCore is YAML-free); the real YAML decode of the template is in ConfigYAMLTests.
    @Test("Runs: an absent block uses the shipped defaults")
    func runsDefaults() throws {
        let r = try JSONDecoder().decode(SkilletConfig.Runs.self, from: Data("{}".utf8))
        #expect(r.k == 3)
        #expect(r.timeout == "10m")
        #expect(r.concurrency == 1)
        #expect(r.confirmAboveTrials == 25)
        #expect(r.maxOutputBytes == 64 << 20)   // 64 MiB default — big enough for a real stream-json session
    }

    @Test("Runs: a partial block keeps other defaults; unmodeled `infra_retries` is ignored")
    func runsPartial() throws {
        let json = #"{"k":5,"confirm_above_trials":10,"infra_retries":2,"max_output_bytes":1048576}"#
        let r = try JSONDecoder().decode(SkilletConfig.Runs.self, from: Data(json.utf8))
        #expect(r.k == 5)
        #expect(r.confirmAboveTrials == 10)
        #expect(r.maxOutputBytes == 1_048_576)   // overrides the 64 MiB default
        #expect(r.timeout == "10m")       // untouched default
        #expect(r.concurrency == 1)       // untouched default
    }

    @Test("Judge: the default provider is claude-code (the F7 amendment)")
    func judgeDefaults() throws {
        let j = try JSONDecoder().decode(SkilletConfig.Judge.self, from: Data("{}".utf8))
        #expect(j.provider == "claude-code")
        #expect(j.model == "claude-sonnet-4-6")
    }
}
