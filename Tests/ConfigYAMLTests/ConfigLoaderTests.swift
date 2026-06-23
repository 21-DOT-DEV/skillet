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
}
