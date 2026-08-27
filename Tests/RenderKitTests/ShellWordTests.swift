import Testing
import Foundation
@testable import RenderKit

/// **A name pasted into a command this tool prints must survive being pasted.**
///
/// Several commands end by printing the exact next command to run. Those lines are built by pasting names
/// into them, and a skill lives in a folder, which may legally be called `My Skill`. Pasted bare that is
/// read as two arguments: measured against a real project, running the printed line gave
/// *"Unexpected argument 'Skill'"* — the tool recommending something that cannot work.
///
/// **Quoted rather than forbidden.** The file this tool generates for itself refuses whitespace outright,
/// and that is right for a name it chooses. A folder name is the user's and already exists; refusing it
/// would mean declining to work with an ordinary folder.
@Suite("Names pasted into printed commands survive being pasted")
struct ShellWordTests {
    @Test("Ordinary names are left exactly as they are",
          arguments: ["demo", "tidy-notes", "a.b.c", "fix.json", "2026-08-22-demo-abcd1234", "a/b", "k=v"])
    func ordinaryNamesUnchanged(name: String) {
        #expect(ShellWord.quoted(name) == name, "quoting something that needs none only adds noise")
    }

    /// The measured case, plus the other punctuation a shell would act on rather than pass through.
    @Test("Names a shell would break apart or act on are quoted",
          arguments: ["My Skill", "a;b", "a|b", "a&b", "a$b", "a`b`", "a>b", "a(b)", "a*b", "", "a\nb"])
    func unsafeNamesQuoted(name: String) {
        let quoted = ShellWord.quoted(name)
        #expect(quoted != name, "it must not be handed over bare")
        #expect(quoted.hasPrefix("'") && quoted.hasSuffix("'"))
    }

    /// **The one character that cannot simply be wrapped.** Inside single quotes everything is literal
    /// except a single quote itself, so one has to close the quoting, be added escaped, and reopen it.
    @Test("A name containing a quote is still written as one word")
    func embeddedQuoteHandled() {
        #expect(ShellWord.quoted("it's") == #"'it'\''s'"#)
    }

    /// The property that matters, checked by reading the result back the way a shell would: whatever goes
    /// in comes out as exactly one word.
    @Test("Whatever goes in comes back as one word",
          arguments: ["My Skill", "it's", "a;b", "plain", "a b c", "'", ""])
    func roundTripsAsOneWord(name: String) throws {
        let script = "printf '%s' " + ShellWord.quoted(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(String(decoding: data, as: UTF8.self) == name,
                "the shell must hand the command exactly the name that went in")
    }
}

/// **A name starting with a hyphen reaches the program as a switch, and quoting cannot stop that.**
///
/// Quotes are removed by the shell, so `skillet run '-demo'` hands over `-demo` exactly as the unquoted
/// form does — measured, both give *"Unknown option '-demo'"*. The repair is the standard end-of-options
/// marker `--`, after which every word is read as a value. The established shell-quoting libraries leave
/// a leading hyphen alone for the same reason: it is not a quoting fault.
@Suite("Commands built for names a parser would read as switches")
struct ShellCommandTests {
    @Test("An ordinary command is unchanged, because one needing no repair should not look repaired")
    func ordinaryUnchanged() {
        #expect(ShellWord.command("skillet run", "demo") == "skillet run demo")
        #expect(ShellWord.command("skillet suggest", "demo", options: ["--proposals fix.json", "--apply"])
                == "skillet suggest demo --proposals fix.json --apply")
    }

    /// **The marker goes last and the switches move ahead of it.** Everything after the marker is read as
    /// a value, so leaving switches behind it turns them into values too — measured:
    /// `skillet suggest -- -demo --proposals fix.json --apply` fails with "3 unexpected arguments".
    @Test("A hyphen-leading name gets the marker, with every switch moved in front of it")
    func hyphenNameTerminated() {
        #expect(ShellWord.command("skillet run", "-demo") == "skillet run -- -demo")
        #expect(ShellWord.command("skillet suggest", "-demo", options: ["--proposals fix.json", "--apply"])
                == "skillet suggest --proposals fix.json --apply -- -demo")
    }

    @Test("A name needing both quoting and the marker gets both")
    func quotingAndTerminatorCompose() {
        #expect(ShellWord.command("skillet run", "-my skill") == "skillet run -- '-my skill'")
    }

    /// A value beginning with a hyphen is taken for the next switch — measured:
    /// `--proposals -fix.json` gives "Missing value for '--proposals'". Joined with `=` it arrives whole.
    @Test("A switch keeps the spaced form, unless its value would be read as another switch")
    func optionValues() {
        #expect(ShellWord.option("--proposals", "fix.json") == "--proposals fix.json")
        #expect(ShellWord.option("--proposals", "-fix.json") == "--proposals=-fix.json")
        #expect(ShellWord.option("--from", "my finding") == "--from 'my finding'")
        // Quoting hides the hyphen from a naive check while leaving it in place for the program.
        #expect(ShellWord.option("--from", "-my finding") == "--from='-my finding'")
    }
}
