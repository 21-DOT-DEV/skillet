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

    /// Eight sections in one decode. This is the assertion that keeps proving the removed workaround
    /// stays removable: the drafting section used to be read separately to hold this type to seven
    /// stored properties, because an eighth made the decoder loop forever. That no longer reproduces
    /// (see the note on `SkilletConfig.Suggest` for what was tested); if it ever returns, this is where
    /// it shows up.
    @Test func decodesEverySectionInOnePass() throws {
        // All eight sections populated. The fixture used to set two of them while the name promised
        // eight — the guard was real (the fault was about how many FIELDS the type has, not how many
        // keys a file sets, so any decode exercised it) but the name overstated what it proved.
        let yaml = """
        project:
          skills_root: skills
        harness:
          default: claude-code
        lint:
          disable: [SKILL-S001]
        runs:
          k: 3
        judge:
          provider: claude-code
          model: claude-sonnet-4-6
        scorers:
          disable: [slop]
        sanitize:
          exempt_paths: [fixtures]
        suggest:
          model: claude-opus-5
        """
        let decoded = try ConfigLoader.decode(yaml)
        #expect(decoded.project?.skillsRoot == "skills")
        #expect(decoded.harness?.default == "claude-code")
        #expect(decoded.lint?.disable == ["SKILL-S001"])
        #expect(decoded.runs?.k == 3)
        #expect(decoded.judge?.model == "claude-sonnet-4-6")
        #expect(decoded.scorers?.disable == ["slop"])
        #expect(decoded.sanitize?.exemptPaths == ["fixtures"])
        #expect(decoded.suggest?.model == "claude-opus-5")
        // A file with no drafting section yields nil rather than throwing.
        #expect(try ConfigLoader.decode("project:\n  skills_root: skills").suggest == nil)
    }
}
