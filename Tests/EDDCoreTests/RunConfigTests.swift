import Testing
import Foundation
import EDDCore

@Suite("Run + judge config")
struct RunConfigTests {
    @Test("skills_root accept-known-good rule: plain relative subpaths only (F33 security pass)")
    func skillsRootValidation() {
        // Safe: plain relative subpaths — including a folder whose NAME contains dots (segment-wise rule).
        for ok in ["skills", "nested/skills", "my..skills", "a/b/c", "./skills"] {
            #expect(SkilletConfig.Project.skillsRootViolation(ok) == nil, "expected '\(ok)' to pass")
        }
        // Rejected: escapes and absolutes — the enumeration-outside-the-project vectors.
        #expect(SkilletConfig.Project.skillsRootViolation("..") == "contains a '..' path segment")
        #expect(SkilletConfig.Project.skillsRootViolation("../../..") == "contains a '..' path segment")
        #expect(SkilletConfig.Project.skillsRootViolation("skills/../..") == "contains a '..' path segment")
        #expect(SkilletConfig.Project.skillsRootViolation("/etc") == "is an absolute path")
        #expect(SkilletConfig.Project.skillsRootViolation("") == "is empty")
    }

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

    @Test("Judge: provider defaults to claude-code; model has NO fallback — required-explicit (§14-4)")
    func judgeDefaults() throws {
        let j = try JSONDecoder().decode(SkilletConfig.Judge.self, from: Data("{}".utf8))
        #expect(j.provider == "claude-code")
        #expect(j.model == nil)   // deliberately no shipped default: `run` refuses without an explicit model
        let explicit = try JSONDecoder().decode(SkilletConfig.Judge.self, from: Data(#"{"model":"m-1"}"#.utf8))
        #expect(explicit.model == "m-1")
    }
}
