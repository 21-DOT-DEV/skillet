import Foundation

/// **A value written into a command line this tool tells you to run.**
///
/// Several commands end by printing the exact next command, so it can be copied and run. Those lines are
/// built by pasting names into them — a skill's name, a file's name — and a name is only safe to paste
/// bare if it contains nothing the shell treats as punctuation. A skill lives in a folder, and a folder
/// may legally be called `My Skill`; pasted bare, that is read as two arguments and the command fails
/// with *"Unexpected argument 'Skill'"*. Measured against a real project before this existed.
///
/// **Quoting rather than forbidding the name.** The rule for the file this tool *generates* is to refuse
/// whitespace outright, and that is right for a name it chooses itself. A folder name is the user's
/// choice and already exists on disk; refusing it would mean this tool declines to work with a perfectly
/// ordinary folder, which is a worse answer than printing a command that survives being pasted.
public enum ShellWord {
    /// Characters that need no quoting anywhere a person is likely to paste this.
    private static let bare = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:+,@%")

    /// The value as it should appear in a command line: unchanged when it is safe bare, and wrapped in
    /// single quotes otherwise.
    ///
    /// Single quotes are used because inside them a shell treats every character literally — there is no
    /// list of further characters to remember. The one thing that cannot appear inside is a single quote,
    /// so an embedded one closes the quoting, adds an escaped quote, and opens it again, which is the
    /// standard way to write it.
    public static func quoted(_ value: String) -> String {
        guard value.isEmpty || value.contains(where: { !bare.contains($0) }) else { return value }
        return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// **A whole command line, arranged so a name starting with a hyphen still reaches the program.**
    ///
    /// Quoting solves one problem and not this one. Quotes are removed by the shell, so
    /// `skillet run '-demo'` hands the program `-demo` exactly as `skillet run -demo` does, and the
    /// program reads a leading hyphen as the start of a switch: measured, *"Unknown option '-demo'"*. The
    /// established shell-quoting libraries leave a leading hyphen alone for this reason — it is not a
    /// quoting fault, and quoting it would only make the broken command look deliberate.
    ///
    /// The fix is the standard end-of-options marker `--`, after which every remaining word is read as a
    /// value however it begins. The published convention says a program building a command whose first
    /// value starts with a hyphen should emit that marker, even when the command takes no switches.
    ///
    /// **The marker has to come last, which is why this takes the switches rather than being pasted in
    /// front of a name.** Everything after the marker is a value, so putting it before the name and
    /// leaving the switches behind it turns those switches into values too — measured:
    /// `skillet suggest -- -demo --proposals fix.json --apply` fails with *"3 unexpected arguments"*.
    /// Switches are therefore moved ahead of the name, and the marker goes immediately before it.
    ///
    /// Nothing changes for an ordinary name: the words come out in the order they were given, because a
    /// command that needs no repair should not look repaired.
    public static func command(_ program: String, _ value: String, options: [String] = []) -> String {
        // **The raw value decides, not the quoted one.** Quoting a name that holds a space produces
        // `'-my skill'`, which no longer begins with a hyphen — but the shell removes those quotes and
        // the program still receives `-my skill`. Testing the quoted form skipped the marker on exactly
        // the names that need both, which is the trap this whole helper exists to close.
        guard value.hasPrefix("-") else {
            return ([program, quoted(value)] + options).joined(separator: " ")
        }
        return ([program] + options + ["--", quoted(value)]).joined(separator: " ")
    }

    /// **A switch and its value, written so a value starting with a hyphen is still read as a value.**
    ///
    /// Separated by a space, a value beginning with a hyphen is taken for the next switch and the command
    /// fails before it starts — measured: `--proposals -fix.json` gives *"Missing value for
    /// '--proposals'"*. Joined with `=`, the same value arrives intact, and the end-of-options marker is
    /// no help here because it would end switch-reading altogether.
    ///
    /// The spaced form is kept for every ordinary value, so the commands people actually see are the ones
    /// they are used to.
    public static func option(_ flag: String, _ value: String) -> String {
        // The raw value decides, for the same reason as above: quoting hides a leading hyphen from this
        // check while leaving it in place for the program that finally reads the word.
        return value.hasPrefix("-") ? "\(flag)=\(quoted(value))" : "\(flag) \(quoted(value))"
    }
}
