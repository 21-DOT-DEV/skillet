import Testing
import Foundation

/// **A skill whose folder name starts with a hyphen used to be handed a command that could not run.**
///
/// A folder called `-demo` was accepted silently and reported as having no problems, and the tool ended by
/// printing `skillet run -demo`. Pasting that gives *"Unknown option '-demo'"* — the word is read as a
/// switch rather than as a name. Quoting does not help: the shell removes the quotes and the program
/// receives the same word. The repair is the standard end-of-options marker `--`, after which every
/// remaining word is read as a value.
///
/// **Two defences, because either alone leaves a hole.** The name is now reported as breaking the
/// published skill-name rule, which stops most people ever reaching this; and the printed commands are
/// built so they work anyway, for anyone who switches that report off — which is a supported thing to do,
/// and is what makes the repair reachable rather than decorative.
///
/// These tests run the printed line rather than checking its text, because checking that a line contains
/// `--` proves nothing about whether the program accepts it.
@Suite("A hyphen-leading skill name is reported, and the printed command still runs", .tags(.integration))
struct DashNameTests {
    private func makeShim(dir: URL) throws -> String {
        let shim = dir.appendingPathComponent("claude-shim.sh")
        try """
        #!/bin/sh
        case "$1" in
          --version) echo "9.9.9 (Claude Code)" ;;
          auth) echo '{"loggedIn":true}' ;;
          *) exit 1 ;;
        esac
        """.write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        return shim.path
    }

    /// A project whose skill folder is named `-demo`; `suppressed` switches the new report off.
    private func makeRepo(suppressed: Bool) throws -> URL {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        let skills = root.appendingPathComponent("skills")
        try FileManager.default.moveItem(at: skills.appendingPathComponent("demo"),
                                         to: skills.appendingPathComponent("-demo"))
        let disable = suppressed ? "lint:\n  disable: [\"SKILL-L012\"]\n" : ""
        try "project:\n  skills_root: skills\n\(disable)".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)
        return root
    }

    /// Splits on spaces except inside single quotes, and unwraps them — what a shell does to these lines.
    private func shellWords(_ line: String) -> [String] {
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

    /// The phrases the argument reader uses when it refuses a line before the program's own work starts.
    private func refusedByTheParser(_ output: String) -> Bool {
        ["Unknown option", "unexpected argument", "unexpected arguments", "Missing value"]
            .contains { output.contains($0) }
    }

    @Test("The name is reported, and no unusable command is printed")
    func reportedAndNoBrokenCommand() async throws {
        let root = try makeRepo(suppressed: false)
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path], environment: ["SKILLET_CLAUDE_CODE_BIN": try makeShim(dir: root)])
        #expect(out.stdout.contains("SKILL-L012"))
        #expect(!out.stdout.contains("skillet run -demo"),
                "the command that cannot run must not be printed: \(out.stdout)")
    }

    @Test("With the report switched off, the printed command is run here and is accepted")
    func printedCommandRuns() async throws {
        let root = try makeRepo(suppressed: true)
        defer { Fixture.remove(root) }
        let shim = try makeShim(dir: root)
        let out = try await SkilletHarness().run(
            ["doctor", "-C", root.path], environment: ["SKILLET_CLAUDE_CODE_BIN": shim])

        let printed = out.stdout.components(separatedBy: "\n").first { $0.contains("→ next:") }
        let line = try #require(printed, "a healthy project must print what to run next: \(out.stdout)")
            .components(separatedBy: "→ next: ").last!.trimmingCharacters(in: .whitespaces)

        var words = shellWords(line)
        #expect(words.first == "skillet", "the printed line must name this tool: \(line)")
        words.removeFirst()
        // **Where the project is goes in front.** Appending it would put it after the end-of-options
        // marker the printed line ends with, where it is read as another name rather than as a switch —
        // this test made that exact mistake first, which is the trap the printed line exists to avoid.
        let ran = try await SkilletHarness().run(["-C", root.path] + words,
                                                 environment: ["SKILLET_CLAUDE_CODE_BIN": shim])
        #expect(!refusedByTheParser(ran.stdout + ran.stderr),
                "the printed line `\(line)` was refused before it started: \(ran.stdout)\(ran.stderr)")
    }
}

/// **A generated command that carries a list of numbers *and* a name starting with a hyphen.**
///
/// The proving command prints a line that applies exactly the edits it proved, so when it proves a subset
/// it adds a list of numbers. That list is read as "keep taking values until the next switch" — and the
/// line also ends with the end-of-options marker and the skill's name, because a name starting with a
/// hyphen would otherwise be read as a switch. Whether the number list stops at that marker instead of
/// swallowing it was reasoned about but never run. It does; this runs it.
@Suite("A generated command survives both a number list and a hyphen-leading name", .tags(.integration))
struct EditsAndDashNameTests {
    @Test("The number list stops at the marker, and the name is read as a name")
    func numberListStopsAtTheMarker() async throws {
        let root = try Fixture.makeLintRepo(description: "a fine description")
        defer { Fixture.remove(root) }
        let skills = root.appendingPathComponent("skills")
        try FileManager.default.moveItem(at: skills.appendingPathComponent("demo"),
                                         to: skills.appendingPathComponent("-demo"))

        let out = try await SkilletHarness().run(
            ["-C", root.path, "suggest", "--proposals", "fix.json", "--apply", "--edits", "1", "2",
             "--", "-demo"])
        // Reaching the tool's own complaint means the line parsed; a usage error would mean it did not.
        #expect(!out.stderr.contains("Unexpected argument"), "the line must parse: \(out.stderr)")
        #expect(!out.stderr.contains("Missing value"), "the number list must not swallow the marker: \(out.stderr)")
        #expect(out.exitCode != 2 || out.stderr.contains("proposals"),
                "any refusal must be about the work, not about how the line was written: \(out.stderr)")
    }
}
