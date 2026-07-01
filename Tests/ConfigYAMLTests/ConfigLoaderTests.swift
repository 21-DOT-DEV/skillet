import Testing
import EDDCore
import ConfigYAML

@Suite("ConfigYAML loader")
struct ConfigLoaderTests {
    @Test("Decodes the F6-relevant slice of skillet.yaml")
    func decodesSlice() throws {
        let yaml = """
        project:
          skills_root: skills
        harness:
          default: claude-code
          matrix: [claude-code, opencode]
          claude-code:
            path: /usr/local/bin/claude
        """
        let config = try ConfigLoader.decode(yaml)
        #expect(config.project?.skillsRoot == "skills")
        #expect(config.harness?.default == "claude-code")
        #expect(config.harness?.matrix == ["claude-code", "opencode"])
        #expect(config.harness?.claudeCode?.path == "/usr/local/bin/claude")
    }

    @Test("An absent harness path decodes to nil (resolution falls through)")
    func absentPath() throws {
        let yaml = """
        project:
          skills_root: skills
        harness:
          default: claude-code
        """
        let config = try ConfigLoader.decode(yaml)
        #expect(config.harness?.claudeCode?.path == nil)
        #expect(config.project?.skillsRoot == "skills")
    }

    @Test("Unmodeled keys are ignored")
    func ignoresUnknownKeys() throws {
        let yaml = """
        project:
          skills_root: skills
        runs:
          k: 3
        harness:
          default: claude-code
          opencode:
            path: /opt/opencode
        """
        let config = try ConfigLoader.decode(yaml)
        #expect(config.project?.skillsRoot == "skills")
        #expect(config.harness?.default == "claude-code")
    }

    @Test("Decodes the F7 runs + judge knobs (k / max_output_bytes / confirm_above_trials / provider / model)")
    func decodesRunsAndJudge() throws {
        let yaml = """
        project:
          skills_root: skills
        runs:
          k: 5
          confirm_above_trials: 40
          max_output_bytes: 1048576
        judge:
          provider: claude-code
          model: claude-sonnet-4-6
        """
        let config = try ConfigLoader.decode(yaml)
        #expect(config.runs?.k == 5)
        #expect(config.runs?.confirmAboveTrials == 40)
        #expect(config.runs?.maxOutputBytes == 1_048_576)
        #expect(config.judge?.provider == "claude-code")
        #expect(config.judge?.model == "claude-sonnet-4-6")
    }
}
