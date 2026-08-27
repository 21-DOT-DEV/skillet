import Testing
import Foundation

/// **The command this tool tells you to run next is actually run here.**
///
/// The loop is: draft an edit, prove it by measuring the skill before and after, then apply it. The
/// proving step ends by printing the exact command that applies what it just proved. Every test until now
/// checked only that this line *appears* — that the right text was printed — which is the same shape as
/// checking a switch is accepted rather than checking it does anything. Nobody had run the printed
/// command to see whether it works, and it is the seam between the two halves of the loop: get it wrong
/// and the tool confidently recommends something that fails, or worse, applies edits nothing measured.
///
/// Free to check — the offline stand-ins answer instead of a model — so there was no reason not to.
@Suite("The command the proving step prints is the command that lands the edit", .tags(.integration))
struct IterateHandoffTests {
    /// Runs the printed line exactly as printed, against the same project.
    private func runAsPrinted(_ line: String, in root: URL) async throws -> SkilletHarness.Output {
        // Split the way a shell would, so a quoted name stays one argument — otherwise this test would
        // pass the very fault it exists to catch.
        var parts = Self.shellWords(line)
        #expect(parts.first == "skillet", "the printed line must name this tool: \(line)")
        parts.removeFirst()
        return try await SkilletHarness().run(["-C", root.path] + parts)
    }

    /// Splits on spaces except inside single quotes, and unwraps them — the small part of a shell's
    /// reading that these printed lines rely on.
    private static func shellWords(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            switch character {
            case "'": quoted.toggle()
            case " " where !quoted:
                if !current.isEmpty { words.append(current); current = "" }
            default: current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private func landLine(_ out: SkilletHarness.Output) throws -> String {
        let line = out.stdout.components(separatedBy: "\n").first { $0.contains("land it:") }
        let said = try #require(line, "a proven edit must print the command that lands it: \(out.stdout)")
        return said.components(separatedBy: "land it: ").last!.trimmingCharacters(in: .whitespaces)
    }

    @Test("Running the printed command applies exactly the edit that was proven")
    func printedCommandLandsTheProvenEdit() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves)
        defer { Fixture.remove(root) }
        let skill = root.appendingPathComponent("skills/demo/SKILL.md")
        #expect(try String(contentsOf: skill, encoding: .utf8).contains("replay-marker: before"))

        let proved = try await IterateFixture.iterate(root, map)
        #expect(proved.exitCode == 0, "\(proved.stderr)")
        let applied = try await runAsPrinted(try landLine(proved), in: root)

        #expect(applied.exitCode == 0, "the command it told you to run must work: \(applied.stderr)")
        let after = try String(contentsOf: skill, encoding: .utf8)
        #expect(after.contains("replay-marker: after"), "and must make the change that was measured")
        #expect(!after.contains("replay-marker: before"))
    }

    /// **A skill whose folder name contains a space still gets a command that runs.** A folder may
    /// legally be called `My Skill`; pasted bare into the printed line it is read as two arguments, and
    /// running exactly what was printed failed with *"Unexpected argument 'Skill'"*. The name is the
    /// user's and already exists on disk, so it is quoted rather than refused.
    @Test("A skill name containing a space still produces a command that runs")
    func spacedSkillNameStillLands() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(verdicts: IterateFixture.improves,
                                                              skillName: "My Skill")
        defer { Fixture.remove(root) }
        let proved = try await IterateFixture.iterate(root, map, [], skillName: "My Skill")
        #expect(proved.exitCode == 0, "\(proved.stderr)")
        let line = try landLine(proved)
        #expect(line.contains("'My Skill'"), "the name must be handed over as one word: \(line)")

        let applied = try await runAsPrinted(line, in: root)
        #expect(applied.exitCode == 0, "the printed command must run: \(applied.stderr)")
        let after = try String(contentsOf: root.appendingPathComponent("skills/My Skill/SKILL.md"),
                               encoding: .utf8)
        #expect(after.contains("replay-marker: after"))
    }

    /// **The subset form is the one most likely to be wrong**, because the proving step assembles it by
    /// adding a switch and a list of numbers to the plain command. If those numbers are not what the
    /// applying step expects, the recommendation either fails or lands edits nothing measured.
    @Test("When only some edits are proven, the printed command lands only those")
    func printedCommandLandsOnlyTheProvenSubset() async throws {
        let (root, _, map) = try await IterateFixture.makeRepo(
            verdicts: IterateFixture.improves,
            secondEdit: (excerpt: "# Guide", replacement: "# Guide (revised)"))
        defer { Fixture.remove(root) }

        let proved = try await IterateFixture.iterate(root, map, ["--edits", "0"])
        #expect(proved.exitCode == 0, "\(proved.stderr)")
        let line = try landLine(proved)
        #expect(line.contains("--edits 0"), "the recommendation must name the subset it proved: \(line)")

        let applied = try await runAsPrinted(line, in: root)
        #expect(applied.exitCode == 0, "the subset command must work: \(applied.stderr)")
        let after = try String(contentsOf: root.appendingPathComponent("skills/demo/SKILL.md"), encoding: .utf8)
        #expect(after.contains("replay-marker: after"), "the proven edit landed")
        #expect(!after.contains("# Guide (revised)"), "and the one that was not measured did not")
    }
}
