import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// The options every paid command answers to the same way. Setup is shared in `PaidCommandFixture`, so no suite owns another's helpers.
@Suite("Paid commands — the options every paid command answers to the same way", .tags(.integration))
struct PaidCommandOptionParityTests {
    // MARK: - narrowing a draft, answered the same way by every command that can

    /// Repeats reached the applying engine in one command and were reported as edit 0 overlapping
    /// itself, at the number reserved for a deliberate safety refusal. The other refused them plainly.
    @Test("Naming the same edit twice is refused identically, as a mistyped command")
    func duplicateEditsRefusedEverywhere() async throws {
        for (name, out) in try await PaidCommandFixture.selections(["--edits", "0", "0"]) {
            #expect(out.exitCode == 2, "\(name) treated a mistyped command as something other than misuse")
            #expect(out.stderr.contains("names edit 0 more than once"), "\(name)")
            #expect(!out.stderr.contains("overlapping"),
                    "\(name) reported an edit overlapping itself, which cannot happen")
        }
    }

    @Test("An edit number the draft does not have is refused identically, naming flag, file and count")
    func outOfRangeEditsRefusedEverywhere() async throws {
        for (name, out) in try await PaidCommandFixture.selections(["--edits", "7"]) {
            #expect(out.exitCode == 2, "\(name)")
            #expect(out.stderr.contains("--edits 7 is not an edit in"), "\(name) must name the flag")
            #expect(out.stderr.contains("(it has 2)"), "\(name) must say how many there are")
            #expect(out.stderr.contains("pick from 0–1"), "\(name) must say what to pick instead")
        }
    }

    /// The one place the shared sentence differs is the verb, because one command writes your files and
    /// the other only measures.
    @Test("The shared refusal says what dropping the flag would do, in each command's own terms")
    func remedyNamesWhatEachCommandWouldDo() async throws {
        let answers = try await PaidCommandFixture.selections(["--edits", "7"])
        let byName = Dictionary(uniqueKeysWithValues: answers.map { ($0.0, $0.1) })
        #expect(try #require(byName["suggest --apply"]).stderr.contains("to apply all 2"))
        #expect(try #require(byName["iterate"]).stderr.contains("to prove all 2"))
    }

    /// **A recording without `--replay` used to launch a real model.** The switch that permits a
    /// test-only option answers "is this allowed here", not "do these options mean anything together" —
    /// so naming a recording on its own passed, was never read, and the command went on to spend against
    /// a real model while the caller believed it was offline.
    /// Spelled out rather than reusing the shared invocations, because those already carry `--replay` —
    /// which is the whole point: with it, naming a recording is correct, and the fault only appears
    /// without it. The first version of this test reused them and so never exercised the case at all.
    @Test("A recording named without --replay is refused, not silently ignored",
          arguments: [["run", "demo", "--replay-map", "recordings.json"],
                      ["iterate", "demo", "--proposals", "fix.json", "--replay-map", "recordings.json", "--yes"]])
    func recordingWithoutReplayRefused(command: [String]) async throws {
        let root = try await PaidCommandFixture.makeRepo(runs: ""); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path] + command)
        #expect(out.exitCode == 2, "\(command[0]) accepted a recording it would never read")
        #expect(out.stderr.contains("--replay-map does nothing without --replay"), "\(command[0])")
        #expect(!out.stderr.contains("could not find the claude-code binary"),
                "\(command[0]) got as far as trying to launch a real model")
    }

    @Test("The measuring command refuses a baseline recording without --replay too")
    func baselineRecordingWithoutReplayRefused() async throws {
        let root = try await PaidCommandFixture.makeRepo(runs: ""); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(
            ["-C", root.path, "run", "demo", "--replay-baseline-map", "recordings.json"])
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("--replay-baseline-map does nothing without --replay"))
    }

    /// The file-reading grader exists for one failure: the run created the file and the contents are
    /// wrong. Only the measuring command offered it, so an edit repairing exactly that could be drafted
    /// and then never proven — the proving command's comparison only ever read what the reply claimed.
    @Test("Both paid commands accept the same two graders, and refuse the same nonsense",
          arguments: [["run", "demo", "--replay"],
                      ["iterate", "demo", "--proposals", "fix.json", "--replay", "--yes"]])
    func graderSelectionIsShared(command: [String]) async throws {
        let bad = try await PaidCommandFixture.makeRepo(runs: ""); defer { Fixture.remove(bad) }
        let refused = try await SkilletHarness().run(["-C", bad.path] + command + ["--judge", "nonsense"])
        #expect(refused.exitCode == 2, "\(command[0]) accepted a grader that does not exist")
        #expect(refused.stderr.contains("unknown judge 'nonsense'"), "\(command[0])")

        let good = try await PaidCommandFixture.makeRepo(runs: ""); defer { Fixture.remove(good) }
        let accepted = try await SkilletHarness().run(["-C", good.path] + command + ["--judge", "grounded-judge"])
        #expect(accepted.exitCode == 0 || accepted.exitCode == 1,
                "\(command[0]) refused the file-reading grader its sibling offers")
        #expect(accepted.stderr.contains("grounded judge includes file contents"),
                "\(command[0]) must warn about the larger, pricier grading requests before spending")
    }

}

/// **Every hidden switch is refused on its own, in both commands that have them.**
///
/// A handful of switches exist only so the test suite can run the tool without a real model and without
/// spending anything. They ship in the released program deliberately — the suite exercises the built
/// program, which is what makes those tests worth having — so each is refused unless an environment
/// variable marks the run as a test.
///
/// One command checked them individually and the other checked them as a group, naming whichever it
/// found first. Both refuse today, because one variable covers all of them; the group form names only one
/// of the switches actually used, and becomes a genuine hole the moment two switches are gated
/// differently. Pinned in both so neither drifts into being the lenient one.
@Suite("Hidden test-only switches are refused one by one, in every command that takes them", .tags(.integration))
struct HiddenSwitchParityTests {
    private static let offTheSuite = ["SKILLET_TEST_SEAMS": ""]   // empty counts as unset

    @Test("Each switch is named in its own refusal", arguments: [
        (command: "run", switches: ["--replay"]),
        (command: "run", switches: ["--replay-map", "map.json"]),
        (command: "run", switches: ["--replay-baseline-map", "map.json"]),
        (command: "iterate", switches: ["--replay"]),
        (command: "iterate", switches: ["--replay-map", "map.json"])
    ])
    func eachSwitchRefusedAlone(command: String, switches: [String]) async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let base = command == "iterate" ? ["-C", root.path, "iterate", "demo", "--proposals", "fix.json"]
                                        : ["-C", root.path, "run", "demo"]
        let out = try await SkilletHarness().run(base + switches, environment: Self.offTheSuite)
        #expect(out.exitCode == 2, "a switch that is not meant to be reachable is a mistyped command")
        #expect(out.stderr.contains("\(switches[0]) is a test-only option"),
                "the refusal must name the switch that was actually used: \(out.stderr)")
    }

    /// Passing two at once must still name the one being refused rather than staying silent about it —
    /// the case the grouped check got wrong.
    @Test("Two switches together are still refused, by name", arguments: ["run", "iterate"])
    func twoSwitchesTogetherRefused(command: String) async throws {
        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let base = command == "iterate" ? ["-C", root.path, "iterate", "demo", "--proposals", "fix.json"]
                                        : ["-C", root.path, "run", "demo"]
        let out = try await SkilletHarness().run(base + ["--replay", "--replay-map", "map.json"],
                                                 environment: Self.offTheSuite)
        #expect(out.exitCode == 2)
        #expect(out.stderr.contains("is a test-only option"))
    }
}
