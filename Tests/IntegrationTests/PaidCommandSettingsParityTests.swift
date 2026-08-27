import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// The settings every paid command reads the same way. Setup is shared in `PaidCommandFixture`, so no suite owns another's helpers.
@Suite("Paid commands — the settings every paid command reads the same way", .tags(.integration))
struct PaidCommandSettingsParityTests {
    // MARK: - settings every paid command must refuse the same way

    @Test("Zero repetitions is refused by every paid command, not measured as a vacuous pass",
          arguments: ["runs:\n  k: 0\n", "runs:\n  k: -3\n"])
    func zeroRepetitionsRefusedEverywhere(runs: String) async throws {
        for (name, out) in try await PaidCommandFixture.answers(runs: runs) {
            #expect(out.exitCode == 2, "\(name) accepted a repetition count of zero or less")
            #expect(out.stderr.contains("runs.k must be at least 1"),
                    "\(name) must name the setting that supplied the value, not a flag nobody typed")
            #expect(!out.stdout.contains("no test scored lower"),
                    "\(name) reported a verdict having measured nothing")
        }
    }

    @Test("A repetition count typed as a flag is refused by every paid command, naming the flag")
    func zeroRepetitionsFromFlagRefusedEverywhere() async throws {
        for (name, out) in try await PaidCommandFixture.answers(runs: "", extra: ["--runs", "0"]) {
            #expect(out.exitCode == 2, "\(name) accepted --runs 0")
            #expect(out.stderr.contains("--runs must be at least 1"),
                    "\(name) must name the flag when the flag is what supplied it")
        }
    }

    @Test("A non-positive output cap is refused by every paid command",
          arguments: ["runs:\n  max_output_bytes: 0\n", "runs:\n  max_output_bytes: -5\n"])
    func badOutputCapRefusedEverywhere(runs: String) async throws {
        for (name, out) in try await PaidCommandFixture.answers(runs: runs) {
            #expect(out.exitCode == 2, "\(name) accepted a non-positive output cap")
            #expect(out.stderr.contains("runs.max_output_bytes must be positive"), "\(name)")
        }
    }

    /// Below zero the cost check (`trials > limit`) is true for every run, so each invocation stops to
    /// ask — and where it cannot ask, refuses. The free preflight printed a tick beside it.
    @Test("A negative ask-before-spending threshold is refused, not forwarded",
          arguments: ["runs:\n  confirm_above_trials: -1\n", "runs:\n  confirm_above_trials: -100\n"])
    func negativeConfirmThresholdRefusedEverywhere(runs: String) async throws {
        for (name, out) in try await PaidCommandFixture.answers(runs: runs) {
            #expect(out.exitCode == 2, "\(name) accepted a threshold that makes every run stop to ask")
            #expect(out.stderr.contains("runs.confirm_above_trials must not be negative"), "\(name)")
        }
    }

    @Test("Zero still means ask about everything, and is accepted")
    func zeroConfirmThresholdIsValid() async throws {
        let root = try await PaidCommandFixture.makeRepo(runs: "runs:\n  confirm_above_trials: 0\n")
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "doctor"])
        #expect(out.stdout.contains("confirm_above_trials=0"), "a valid setting, reported as one")
        #expect(!out.stdout.contains("✗ config.runs"))
    }

    @Test("A time limit the tool cannot read is refused, never silently replaced",
          arguments: [#"runs:{TIMEOUT}"# .replacingOccurrences(of: "{TIMEOUT}", with: "\n  timeout: \"banana\"\n"),
                      "runs:\n  timeout: \"10 minutes\"\n",
                      "runs:\n  timeout: \"1 h\"\n"])
    func unreadableTimeLimitRefusedEverywhere(runs: String) async throws {
        for (name, out) in try await PaidCommandFixture.answers(runs: runs) {
            #expect(out.exitCode == 2, "\(name) accepted a time limit it cannot read, and silently used ten minutes")
            #expect(out.stderr.contains("runs.timeout is not a duration"), "\(name)")
        }
    }

    /// A test with no instruction to send cannot run. Left through, the measuring command counted it as
    /// a failed test while the proving command compared nothing with nothing, called it no change, and
    /// offered the command that lands the edit. Refused for free now, from one place, with the number
    /// this project already gives a test file that is wrong in this way.
    @Test("A test with no prompt is refused before spending, by every paid command",
          arguments: [#"{"skill_name":"demo","evals":[{"id":"e1","expectations":["did the thing"]}]}"#,
                      #"{"skill_name":"demo","evals":[{"id":"e1","prompt":"   ","expectations":["did the thing"]}]}"#])
    func promptlessEvalRefusedEverywhere(evals: String) async throws {
        for (name, out) in try await PaidCommandFixture.answers(runs: "", evalsRaw: evals) {
            #expect(out.exitCode == 4, "\(name) let a test that cannot run through")
            #expect(out.stderr.contains("has no prompt to send"), "\(name)")
            #expect(!out.stdout.contains("no test scored lower"),
                    "\(name) drew a verdict from a test that never ran")
        }
    }

    /// **Whether the reading library says where in the file the fault is.** It does on one platform and not
    /// on the other, where the message is only "the given data was not valid JSON". So the position is a
    /// capability of the machine, not a promise this tool can keep everywhere — asserting it unconditionally
    /// failed the whole suite on Linux. Asked here the same way the program itself asks, so the test and
    /// the code cannot disagree about what is available.
    private static let readerReportsPosition: Bool = {
        do {
            _ = try JSONSerialization.jsonObject(with: Data("{ this is not json".utf8))
            return false
        } catch {
            let described = (error as NSError).userInfo["NSDebugDescription"] as? String
            return described?.lowercased().contains("line") == true
        }
    }()

    /// The same unreadable file used to give the exact character position from one command and nothing at
    /// all from the other. Both now explain it the same way, in terms of the reader's own file, and
    /// neither names this program's internals. Where the machine can say *where*, both say it.
    @Test("An unreadable test file is explained the same way, and in terms of the file")
    func unreadableFileExplainedTheSameWay() async throws {
        for (name, out) in try await PaidCommandFixture.answers(runs: "", evalsRaw: "{ this is not json") {
            #expect(out.exitCode == 4, "\(name)")
            #expect(out.stderr.contains("evals.json"), "\(name) must name the reader's own file")
            if Self.readerReportsPosition {
                #expect(out.stderr.contains("line 1, column 4"), "\(name) must say where the fault is")
            }
            for internalName in ["DecodingError", "NSCocoaErrorDomain", "NSJSONSerializationErrorIndex"] {
                #expect(!out.stderr.contains(internalName),
                        "\(name) named this program's internals instead of the reader's file")
            }
        }
    }

    /// **The name is the key every comparison joins on**, so two tests answering to one leaves a
    /// comparison unable to say which it means. Measured before this check existed: two tests both named
    /// `same`, the first improving and the second getting worse, produced a single row reading `+1.00`,
    /// the verdict "no test scored lower", and an offer to apply the edit.
    @Test("Two tests with one name are refused by every paid command, before spending")
    func repeatedTestNameRefusedEverywhere() async throws {
        let evals = #"""
        {"skill_name":"demo","evals":[
         {"id":"same","prompt":"a","expectations":["did the thing"]},
         {"id":"same","prompt":"b","expectations":["did the thing"]}]}
        """#
        for (name, out) in try await PaidCommandFixture.answers(runs: "", evalsRaw: evals) {
            #expect(out.exitCode == 4, "\(name) accepted a name that identifies two tests")
            #expect(out.stderr.contains("two evals are both named 'same'"), "\(name)")
            #expect(!out.stdout.contains("no test scored lower"),
                    "\(name) drew a verdict from a comparison missing a test")
        }
    }

    /// A test may leave its name out and be named from its own content, so the check has to compare the
    /// names actually used — two tests with the same prompt collide even though neither names anything.
    @Test("Two unnamed tests with the same prompt are caught too")
    func repeatedDerivedNameRefusedEverywhere() async throws {
        let evals = #"""
        {"skill_name":"demo","evals":[
         {"prompt":"identical prompt","expectations":["did the thing"]},
         {"prompt":"identical prompt","expectations":["did the thing"]}]}
        """#
        for (name, out) in try await PaidCommandFixture.answers(runs: "", evalsRaw: evals) {
            #expect(out.exitCode == 4, "\(name) compared only the names written down")
            #expect(out.stderr.contains("are both named"), "\(name)")
        }
    }

    /// The name has to survive the file being edited around it, or a test quietly inherits another
    /// test's accumulated history. Two orderings of the same two tests must produce the same two names.
    @Test("Reordering the tests file does not rename the tests")
    func namesSurviveReordering() async throws {
        func names(_ order: [String]) async throws -> [String] {
            let cases = order.map { #"{"prompt":"\#($0)","expectations":["did the thing"]}"# }
            let root = try await PaidCommandFixture.makeRepo(
                runs: "", evalsRaw: #"{"skill_name":"demo","evals":[\#(cases.joined(separator: ","))]}"#)
            defer { Fixture.remove(root) }
            let out = try await SkilletHarness().run(
                ["-C", root.path, "run", "demo", "--replay", "--runs", "1", "--json"])
            let payload = try #require(try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any])
            let behavior = (payload["behavior"] as? [String: Any]) ?? payload
            return ((behavior["evals"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }.sorted()
        }
        let forwards = try await names(["summarise the report", "tidy the notes"])
        let backwards = try await names(["tidy the notes", "summarise the report"])
        #expect(forwards == backwards, "moving a test must not rename it — got \(forwards) then \(backwards)")
        #expect(!forwards.contains { $0.hasPrefix("eval-") }, "names must not be positions: \(forwards)")
    }

    // MARK: - settings every paid command must agree about

    /// The threshold counts **trials**, and the proving command already counts double for its two
    /// measurements — so it already asks at half the repetitions. Giving it a lower threshold on top
    /// counted the same cost twice; it had 20 where the declared default is 25.
    @Test("Both commands take the ask-before-spending threshold from the same declared default")
    func sharedConfirmationThreshold() async throws {
        // 24 trials for either command: under the declared default of 25, so neither may ask.
        let runRoot = try await PaidCommandFixture.makeRepo(runs: ""); defer { Fixture.remove(runRoot) }
        let iterateRoot = try await PaidCommandFixture.makeRepo(runs: ""); defer { Fixture.remove(iterateRoot) }
        let run = try await SkilletHarness().run(
            ["-C", runRoot.path, "run", "demo", "--replay", "--runs", "24", "--no-input"])
        let iterate = try await SkilletHarness().run(
            ["-C", iterateRoot.path, "iterate", "demo", "--proposals", "fix.json", "--replay",
             "--runs", "12", "--no-input"])
        #expect(run.exitCode != 5, "run asked below the shared threshold")
        #expect(iterate.exitCode != 5, "iterate asked below the shared threshold — its own number had drifted")
    }

    /// The declared default is 64 MiB. The proving command had 4 MiB typed by hand, small enough to cut
    /// off a long session and record the attempt as a failure having nothing to do with the skill.
    @Test("The free preflight reports the same numbers the paid commands run on")
    func preflightAgreesWithTheDefaults() async throws {
        let root = try await PaidCommandFixture.makeRepo(runs: "")
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "doctor", "--json"])
        #expect(out.stdout.contains("max_output_bytes=67108864"), "64 MiB, from the one place that declares it")
        #expect(out.stdout.contains("confirm_above_trials=25"))
    }

    @Test("The free preflight fails on a time limit it cannot read, so the fault costs nothing to find")
    func preflightCatchesTheTimeLimit() async throws {
        let root = try await PaidCommandFixture.makeRepo(runs: "runs:\n  timeout: \"10 minutes\"\n")
        defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "doctor"])
        #expect(out.exitCode == 3, "doctor reports an unusable environment")
        #expect(out.stdout.contains("config.runs") || out.stderr.contains("config.runs"))
    }
}
