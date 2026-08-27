import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The split output of a command: machine/primary text for stdout, human chatter/errors for stderr
/// (design §5.5, clig.dev). Produced purely by ``Renderer`` so it can be asserted in unit tests;
/// written to the real handles by ``Console``.
public struct Rendering: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    public init(stdout: String = "", stderr: String = "") {
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Writes a ``Rendering`` to the process's real stdout/stderr, and answers TTY questions.
public enum Console {
    public static func emit(_ rendering: Rendering) {
        if !rendering.stdout.isEmpty {
            FileHandle.standardOutput.write(Data(rendering.stdout.utf8))
        }
        if !rendering.stderr.isEmpty {
            FileHandle.standardError.write(Data(rendering.stderr.utf8))
        }
    }

    /// Whether stdout is attached to a terminal (drives `--color auto`).
    public static func isStdoutTTY() -> Bool {
        isatty(FileHandle.standardOutput.fileDescriptor) != 0
    }

    /// Whether stdin is attached to a terminal — required (alongside the stream the question is written
    /// on) before an interactive prompt, so a piped/redirected stdin fails like `--no-input` rather than
    /// blocking on or consuming unexpected `readLine()` input.
    public static func isStdinTTY() -> Bool {
        isatty(FileHandle.standardInput.fileDescriptor) != 0
    }

    /// **Whether the stream questions and notes are written on is attached to a terminal.**
    ///
    /// Asking someone a question needs two things: that they can see it, and that their answer can reach
    /// us. The first is decided by the stream the question goes out on — this one — and the second by the
    /// stream the answer comes back on. The stream ordinary results go out on decides neither.
    ///
    /// It existed only for results, and was being used to decide both. So saving results to a file while
    /// watching the screen — `skillet run demo | tee log.txt` — made the tool conclude nobody was there
    /// and stop, refusing to ask a question that would have appeared on screen and could have been
    /// answered. A well-known project fixed the same mistake in a change titled "Check stdin rather than
    /// stdout for interactive terminals".
    public static func isStderrTTY() -> Bool {
        isatty(FileHandle.standardError.fileDescriptor) != 0
    }
}
