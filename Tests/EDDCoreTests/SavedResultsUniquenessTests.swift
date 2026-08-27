import Testing
import Foundation
import EDDCore

/// The saved results file is the **second door** results come in by: written by an older version, edited
/// by hand, or merged from a branch — and read back months later to rebuild a comparison, when nobody is
/// watching. Each entry carries a test name, and that name is what the comparison joins on.
@Suite("Re-reading saved results — a repeated test name is refused")
struct SavedResultsUniquenessTests {
    /// A saved file whose per-test entries carry the names given.
    private func saved(withArm names: [String], baseline: [String] = []) throws -> BenchmarkFile {
        // The two arms are told apart by an `arm` marker. Naming the wrong key here silently filed the
        // without-skill entries as with-skill ones, so both tests exercised one path and the other was
        // untested — caught only because removing the with-skill check failed the baseline test too.
        func entry(_ id: String, baseline: Bool) -> String {
            let marker = baseline ? #","arm":"baseline"# + "\"" : ""
            return #"{"eval_id":"\#(id)","flaky":false,"mean_pass_rate":1,"pass_power_k":1,"perfect_passes":1,"runs":1\#(marker)}"#
        }
        let perEval = (names.map { entry($0, baseline: false) }
                       + baseline.map { entry($0, baseline: true) }).joined(separator: ",")
        let json = #"""
        {"consistency":{"flaky_eval_ids":[],"k":1,"meaningful":false,"per_eval":[\#(perEval)],"suite_pass_power_k":1},
         "metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[],
         "run_summary":{}}
        """#
        return try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
    }

    @Test("Distinct names rebuild the report as before")
    func distinctRebuilds() throws {
        let report = try RunReport(benchmark: saved(withArm: ["a", "b"]))
        #expect(report.evals.count == 2)
    }

    /// **Refused as a bad file, blaming the file and not the tool.** Reading a saved file is not the same
    /// as building results in memory: this one came from somewhere else and may be old, hand-edited, or
    /// damaged. The refusal used to travel as a bare "two entries share a name", which the command layer
    /// could only classify as "something went wrong inside skillet" — the wrong file named, the wrong
    /// exit code, and no way to act on it. It now says which file, which name, and what to do.
    /// The third arm — the one measuring whether a model reaches for the right skill — was checked when
    /// results come straight from a run, and not when they are read back from a saved file. Measured
    /// before the fix: one routing check named twice produced two rows for one check and a score of
    /// `0.5`, a half-success invented from a single check recorded once as passing and once as failing.
    @Test("A repeated routing name in a saved file is refused, as a bad file")
    func repeatedTriggerRefused() throws {
        func entry(_ id: String, passes: Int) -> String {
            #"{"eval_id":"\#(id)","axis":"trigger","flaky":false,"mean_pass_rate":1,"#
                + #""pass_power_k":\#(passes),"perfect_passes":\#(passes),"runs":1}"#
        }
        let json = #"""
        {"consistency":{"flaky_eval_ids":[],"k":1,"meaningful":false,
          "per_eval":[\#(entry("t", passes: 1)),\#(entry("t", passes: 0))],"suite_pass_power_k":1},
         "metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[], "run_summary":{}}
        """#
        let file = try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
        expectBadFile("t", in: file, "a repeated routing name doubles the table and the score beneath it")
    }

    /// Distinct routing names are unaffected, so the refusal is not a blanket one.
    @Test("Distinct routing names are read back as before")
    func distinctTriggerNamesRead() throws {
        func entry(_ id: String) -> String {
            #"{"eval_id":"\#(id)","axis":"trigger","flaky":false,"mean_pass_rate":1,"#
                + #""pass_power_k":1,"perfect_passes":1,"runs":1}"#
        }
        let json = #"""
        {"consistency":{"flaky_eval_ids":[],"k":1,"meaningful":false,
          "per_eval":[\#(entry("a")),\#(entry("b"))],"suite_pass_power_k":1},
         "metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[], "run_summary":{}}
        """#
        let file = try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
        let report = try RunReport(benchmark: file)
        #expect(report.trigger?.evals.map(\.id) == ["a", "b"])
        #expect(report.trigger?.passK == 1)
    }

    private func expectBadFile(_ name: String, in file: BenchmarkFile,
                               _ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation) {
        do {
            _ = try RunReport(benchmark: file)
            Issue.record(comment, sourceLocation: sourceLocation)
        } catch let error as EDDError {
            guard case let .invalidArtifact(path, reason, fix) = error else {
                Issue.record("a damaged file must report as a bad file, not as \(error.kind)",
                             sourceLocation: sourceLocation)
                return
            }
            #expect(path == "benchmark.json", "the message has to say which file", sourceLocation: sourceLocation)
            #expect(reason.contains(name), "and which name is repeated", sourceLocation: sourceLocation)
            #expect(fix?.isEmpty == false, "and what to do about it", sourceLocation: sourceLocation)
        } catch {
            Issue.record("a damaged file must report as a bad file, not as \(error)",
                         sourceLocation: sourceLocation)
        }
    }

    /// The fault this closes: the with-skill side was passed straight through unchecked, so a repeat
    /// there produced a wrong score and a wrong comparison from a file nobody would think to suspect.
    @Test("A repeated name on the with-skill side is refused, as a bad file")
    func repeatedWithArmRefused() throws {
        expectBadFile("same", in: try saved(withArm: ["same", "same"]),
                      "a repeated with-skill name scores and pairs the wrong results")
    }

    @Test("A repeated name on the without-skill side is refused too, as a bad file")
    func repeatedBaselineRefused() throws {
        expectBadFile("same", in: try saved(withArm: ["a"], baseline: ["same", "same"]),
                      "a repeated without-skill name pairs the wrong two results")
    }
}

/// **The same rule, at the moment a live run turns raw results into a report.**
///
/// A run produces a list of results, one per test. Two of them carrying the same test name has no defined
/// meaning: the name is what every later comparison joins on. The saved-file path was made to refuse that
/// on both sides; the live path checked only the side it looked names up in, on the reasoning that the
/// other is merely walked in order. Walking a repeat is not harmless, which is what these pin.
@Suite("A live run refuses a repeated test name on every arm")
struct LiveRunUniquenessTests {
    private func result(_ id: String, passed: Bool) -> EvalResult {
        EvalResult(evalId: id, trials: [TrialResult(
            exit: .passed,
            verdicts: [Verdict(criterion: "c", passed: passed, rationale: "r",
                               judgeId: "j", model: "m", judgePromptVersion: "v")],
            durationSeconds: 1)])
    }

    /// Measured before the fix: three results for two distinct tests produced a report claiming three
    /// tests — one passed, one failed, and the same name appearing twice as though the two were
    /// independent.
    @Test("A repeated name in the run's own results is refused, not counted twice")
    func repeatedWithArmRefused() {
        #expect(throws: RepeatedName(name: "a")) {
            _ = try RunReport(skill: "demo",
                              results: [result("a", passed: true), result("a", passed: false),
                                        result("b", passed: true)])
        }
    }

    /// The comparison against a run made without the skill paired the *same* without-skill result against
    /// both copies, so one measurement counted twice in the average while the table showed two rows.
    @Test("A repeated name is refused before it can be paired twice against one baseline")
    func repeatedWithArmNotPairedTwice() {
        #expect(throws: RepeatedName(name: "a")) {
            _ = try RunReport(skill: "demo",
                              results: [result("a", passed: true), result("a", passed: false)],
                              baseline: [result("a", passed: false)])
        }
    }

    /// The without-skill side keeps the guarantee it already had — so the fix above did not move the
    /// check from one arm to another.
    @Test("A repeated name on the without-skill side is still refused")
    func repeatedBaselineStillRefused() {
        #expect(throws: RepeatedName(name: "dup")) {
            _ = try RunReport(skill: "demo", results: [result("a", passed: true)],
                              baseline: [result("dup", passed: true), result("dup", passed: false)])
        }
    }

    /// The third arm — the one measuring whether a model reaches for the right skill — was unchecked for
    /// the same reason and is checked now, so no arm is the exception.
    @Test("A repeated name on the routing arm is refused too")
    func repeatedTriggerRefused() {
        func routing(_ id: String) -> TriggerEvalResult {
            TriggerEvalResult(evalId: id, query: "q", shouldTrigger: true,
                              trials: [TriggerTrialResult(exit: .passed, firedTarget: true, firedOther: [])])
        }
        #expect(throws: RepeatedName(name: "t")) {
            _ = try RunReport(skill: "demo", results: [result("a", passed: true)],
                              trigger: [routing("t"), routing("t")])
        }
    }

    @Test("Distinct names build a report as before, one row each and in the order measured")
    func distinctNamesUnaffected() throws {
        let report = try RunReport(skill: "demo",
                                   results: [result("b", passed: true), result("a", passed: false)])
        #expect(report.evals.map(\.id) == ["b", "a"], "the order the run measured them in is kept")
        #expect(report.passed == 1)
        #expect(report.failed == 1)
    }
}

/// **Why a repeated test name ends two different ways, and that this is on purpose.**
///
/// Every comparison this tool makes joins results by test name, so two results sharing one has no defined
/// meaning and is always refused. *Where* it is refused decides what a person is told:
///
/// - Reading a saved results file, the file is at fault — it may be old, hand-edited, or merged from
///   somewhere else — so the refusal names the file and how to fix it, and the program stops with the
///   code meaning "that file is not valid".
/// - Building a report from a run that just happened, no file can honestly be blamed. The names came
///   either from a check that already refuses repeats before any money is spent, naming the file and the
///   fix, or from numbering generated in a loop. A repeat arriving here means one of those two failed,
///   which is this tool's fault — so it stops with the code meaning "a defect in skillet", carrying the
///   same sentence about which name repeated and a link to report it.
///
/// Without this, the difference reads as one of the two paths having been forgotten.
@Suite("A repeated name is reported differently by path, on purpose")
struct RepeatedNameClassificationTests {
    private func result(_ id: String) -> EvalResult {
        EvalResult(evalId: id, trials: [TrialResult(
            exit: .passed,
            verdicts: [Verdict(criterion: "c", passed: true, rationale: "r",
                               judgeId: "j", model: "m", judgePromptVersion: "v")],
            durationSeconds: 1)])
    }

    @Test("From a run that just happened: reported as this tool's own defect, still naming the test")
    func liveRunReportsToolDefect() {
        do {
            _ = try RunReport(skill: "demo", results: [result("same"), result("same")])
            Issue.record("a repeated name must be refused wherever it appears")
        } catch {
            // How the command layer classifies anything it did not anticipate.
            let classified = EDDError.internalError(detail: "\(error)")
            #expect(classified.exitCode.rawValue == 70, "the code meaning a defect in the tool itself")
            #expect(classified.message.contains("same"), "and it still says which name repeated")
            #expect(classified.message.contains("not a problem with your project"),
                    "because the checks that should have caught this are the tool's, not the project's")
        }
    }

    /// The other path, side by side, so the difference is visible as a decision rather than an accident.
    @Test("From a saved file: reported as that file being invalid, naming the file")
    func savedFileReportsBadFile() throws {
        let file = try saved(withArm: ["same", "same"])
        do {
            _ = try RunReport(benchmark: file)
            Issue.record("a repeated name must be refused wherever it appears")
        } catch let error as EDDError {
            #expect(error.exitCode.rawValue == 4, "the code meaning that file is not valid")
            #expect(error.message.contains("benchmark.json"), "and it says which file")
        }
    }

    /// A saved file whose per-test entries carry the names given — same shape the suite above uses.
    private func saved(withArm names: [String]) throws -> BenchmarkFile {
        let perEval = names.map {
            #"{"eval_id":"\#($0)","flaky":false,"mean_pass_rate":1,"pass_power_k":1,"perfect_passes":1,"runs":1}"#
        }.joined(separator: ",")
        let json = #"""
        {"consistency":{"flaky_eval_ids":[],"k":1,"meaningful":false,"per_eval":[\#(perEval)],"suite_pass_power_k":1},
         "metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[], "run_summary":{}}
        """#
        return try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
    }
}

/// **A block carried forward from a saved file keeps the name it was found under.**
///
/// A results file holds one block of figures per run. When a later run measures only the "does the model
/// reach for this skill" check, the earlier run's figures are carried through unchanged so the file keeps
/// both. Which block was picked up and which name it was written back under were decided in two separate
/// places, from two different rules — one preferring the single-run block, the other preferring the
/// comparison name. A file holding both then had its single-run figures written back under the comparison
/// name: the label said one thing and the numbers were the other's, and the block that name belonged to
/// was dropped entirely.
///
/// skillet itself never writes both names — a comparison run replaces the whole thing — so this needs a
/// file merged or edited by hand. It is pinned because the mismatch is silent and the file is what later
/// runs and any viewer read.
@Suite("Carrying a run's figures forward keeps their label attached")
struct CarriedSummaryLabelTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")

    /// A saved file whose blocks are told apart by their numbers, so a swap is visible.
    private func prior(_ blocks: [String: Double]) throws -> BenchmarkFile {
        let summaries = blocks.map {
            #""\#($0.key)":{"pass_rate":{"mean":\#($0.value),"stddev":0,"min":0,"max":0}}"#
        }.joined(separator: ",")
        let json = #"""
        {"consistency":{"k":1,"meaningful":false,"per_eval":[],"suite_pass_power_k":1,"flaky_eval_ids":[]},
         "metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[], "run_summary":{\#(summaries)}}
        """#
        return try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
    }

    private func carriedForward(_ blocks: [String: Double]) throws -> [String: JSONValue] {
        let routing = [TriggerEvalResult(evalId: "t", query: "q", shouldTrigger: true,
                                         trials: [TriggerTrialResult(exit: .passed, firedTarget: true, firedOther: [])])]
        let merged = try BenchmarkFile(skill: "demo", behavioral: nil, trigger: routing,
                                       harness: "replay", k: 1, provenance: provenance,
                                       preserving: try prior(blocks))
        return merged.runSummary ?? [:]
    }

    private func mean(_ summary: [String: JSONValue], _ key: String) -> Double? {
        summary[key]?.objectValue?["pass_rate"]?.objectValue?["mean"]?.numberValue
    }

    /// The case that was wrong: both names present, and the single-run figures reappeared under the
    /// comparison name while the comparison figures were thrown away.
    @Test("With both names present, each keeps its own figures")
    func bothNamesKeepTheirOwn() throws {
        let summary = try carriedForward(["default": 0.11, "with_skill": 0.99])
        #expect(mean(summary, "with_skill") != 0.11,
                "the single-run figures must not reappear under the comparison name")
        #expect(mean(summary, "default") == 0.11 || mean(summary, "with_skill") == 0.99,
                "whichever is carried keeps the numbers that belong to its name")
    }

    @Test("Only the single-run name present ⇒ carried under that name")
    func singleRunNameCarried() throws {
        let summary = try carriedForward(["default": 0.11])
        #expect(mean(summary, "default") == 0.11)
        #expect(summary["with_skill"] == nil)
    }

    @Test("Only the comparison name present ⇒ carried under that name")
    func comparisonNameCarried() throws {
        let summary = try carriedForward(["with_skill": 0.99])
        #expect(mean(summary, "with_skill") == 0.99)
        #expect(summary["default"] == nil)
    }
}

/// **A count that cannot be a count stops the file being scored, rather than removing a test from it.**
///
/// A saved results file is re-read to rebuild a score without running anything again. Each entry says how
/// many times a test ran and how many of those runs passed; both must be whole numbers. An entry saying
/// something else — `2.5`, or a word — used to be passed over in silence, and the score was then worked
/// out from the entries that remained: a confident figure covering fewer tests than the file lists, with
/// nothing marking it as such. Quietly shrinking what a score covers can only push the figure up, which is
/// why benchmark-reporting guidance names it as untrustworthy.
@Suite("A count that is not a whole number stops the file being scored")
struct NonWholeCountTests {
    /// A saved file with one ordinary entry and one whose named count is whatever is given.
    private func saved(_ field: String, _ raw: String) throws -> BenchmarkFile {
        let broken = #"{"eval_id":"broken","flaky":false,"mean_pass_rate":1,"pass_power_k":1,"# +
            (field == "runs" ? #""perfect_passes":1,"runs":\#(raw)"# : #""perfect_passes":\#(raw),"runs":1"#) + "}"
        let json = #"""
        {"consistency":{"flaky_eval_ids":[],"k":1,"meaningful":false,"per_eval":[
            {"eval_id":"fine","flaky":false,"mean_pass_rate":1,"pass_power_k":1,"perfect_passes":1,"runs":1},
            \#(broken)],"suite_pass_power_k":1},
         "metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[], "run_summary":{}}
        """#
        return try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
    }

    @Test("A fractional or non-numeric count refuses the file, naming the test and what to do",
          arguments: [("runs", "2.5"), ("perfect_passes", "0.5"), ("runs", "\"three\""), ("perfect_passes", "null")])
    func refusesAndSaysWhy(field: String, raw: String) throws {
        do {
            _ = try RunReport(benchmark: try saved(field, raw))
            Issue.record("a count that is not a whole number must stop the file being scored")
        } catch let error as EDDError {
            guard case let .invalidArtifact(path, reason, fix) = error else {
                Issue.record("a damaged file must report as a bad file, not as \(error.kind)"); return
            }
            #expect(path == "benchmark.json", "it says which file")
            #expect(reason.contains("broken"), "and which test: \(reason)")
            #expect(reason.contains(field), "and which of its counts")
            #expect(fix?.isEmpty == false, "and what to do")
        }
    }

    /// **Two counts that cannot both be true describe no run, so the file is refused.** A count below
    /// none, or more runs passing than were ever attempted, used to be accepted and turned into a
    /// plausible-looking verdict instead of a rejection: measured, five passes out of three attempts read
    /// as "this test is unreliable", and a negative attempt count reached the printed summary as
    /// `observed k=-1`.
    @Test("A pair of counts that cannot both be true refuses the file",
          arguments: [("perfect_passes", "-1"), ("runs", "-1")])
    func negativeCountRefused(field: String, raw: String) throws {
        do {
            _ = try RunReport(benchmark: try saved(field, raw))
            Issue.record("a count below none describes no run and must stop the file being scored")
        } catch let error as EDDError {
            guard case let .invalidArtifact(_, reason, _) = error else {
                Issue.record("must report as a bad file, not as \(error.kind)"); return
            }
            #expect(reason.contains("broken"), "it says which test: \(reason)")
        }
    }

    @Test("More runs passing than were attempted refuses the file")
    func morePassesThanRunsRefused() throws {
        // The entry says five of its runs passed, and that it ran once.
        do {
            _ = try RunReport(benchmark: try saved("perfect_passes", "5"))
            Issue.record("more passes than attempts describes no run")
        } catch let error as EDDError {
            guard case let .invalidArtifact(_, reason, fix) = error else {
                Issue.record("must report as a bad file, not as \(error.kind)"); return
            }
            #expect(reason.contains("5"), "it says how many: \(reason)")
            #expect(fix?.contains("attempted") == true, "and why that cannot be: \(fix ?? "")")
        }
    }

    /// The ordinary shapes stay accepted, so the refusal is not a blanket one: none passing, all passing,
    /// and nothing attempted at all.
    @Test("Coherent counts are still read", arguments: [("0", "3"), ("3", "3"), ("0", "0")])
    func coherentCountsStillRead(passes: String, runs: String) throws {
        let json = #"""
        {"consistency":{"flaky_eval_ids":[],"k":1,"meaningful":false,"per_eval":[
            {"eval_id":"fine","flaky":false,"mean_pass_rate":1,"pass_power_k":1,
             "perfect_passes":\#(passes),"runs":\#(runs)}],"suite_pass_power_k":1},
         "metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[], "run_summary":{}}
        """#
        let file = try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
        #expect(try RunReport(benchmark: file).evals.count == 1)
    }

    /// **The same number written two ways is the same number.** A file format has no separate whole-number
    /// type, so `2.0` is two and must keep working — the test is the value, not how it was written.
    @Test("A whole number written with a decimal point is still a whole number")
    func wholeNumberWithDecimalPointIsFine() throws {
        let report = try RunReport(benchmark: try saved("runs", "2.0"))
        #expect(report.evals.count == 2, "both tests are scored")
        #expect(report.evals.first { $0.id == "broken" }?.recorded == 2)
    }

    /// The other half, so the refusal cannot be satisfied by refusing everything.
    @Test("An ordinary file is still scored")
    func ordinaryFileStillScored() throws {
        #expect(try RunReport(benchmark: try saved("runs", "1")).evals.count == 2)
    }
}

/// **A test's name is the key every result is matched up by, so an entry without a usable one is
/// refused.** Two shapes used to pass silently: an entry with no name was dropped and the score computed
/// from what remained, and a name written as `1.5` was turned into the text `"1.5"` and used as a real
/// test name. The counts in the same entry are already refused when they cannot be counts, so the more
/// important field was being treated the more leniently.
@Suite("An entry without a usable test name refuses the file")
struct UnusableTestNameTests {
    private func saved(_ nameField: String) throws -> BenchmarkFile {
        let json = #"""
        {"consistency":{"flaky_eval_ids":[],"k":1,"meaningful":false,"per_eval":[
            {"eval_id":"fine","flaky":false,"mean_pass_rate":1,"pass_power_k":1,"perfect_passes":1,"runs":1},
            {\#(nameField)"flaky":false,"mean_pass_rate":1,"pass_power_k":1,"perfect_passes":1,"runs":1}],
          "suite_pass_power_k":1},
         "metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[], "run_summary":{}}
        """#
        return try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
    }

    @Test("A name that cannot name a test refuses the file, saying what was there", arguments: [
        (#""eval_id":1.5,"#, "1.5"), (#""eval_id":[],"#, "list"), (#""eval_id":{},"#, "object"),
        (#""eval_id":null,"#, "")
    ])
    func unusableNameRefused(field: String, mentions: String) throws {
        do {
            _ = try RunReport(benchmark: try saved(field))
            Issue.record("an entry that cannot be named must stop the file being scored")
        } catch let error as EDDError {
            guard case let .invalidArtifact(path, reason, fix) = error else {
                Issue.record("must report as a bad file, not as \(error.kind)"); return
            }
            #expect(path == "benchmark.json")
            #expect(fix?.isEmpty == false, "and say what to do")
            if !mentions.isEmpty {
                #expect(reason.contains(mentions), "and describe what was there: \(reason)")
            }
        }
    }

    @Test("An entry with no name at all refuses the file too")
    func missingNameRefused() throws {
        #expect(throws: EDDError.self) { _ = try RunReport(benchmark: try saved("")) }
    }

    /// Names written as whole numbers are ordinary in these files and keep working, read as their digits.
    @Test("A whole number is still a usable name")
    func wholeNumberNameAccepted() throws {
        let report = try RunReport(benchmark: try saved(#""eval_id":7,"#))
        #expect(report.evals.map(\.id).sorted() == ["7", "fine"])
    }
}

/// **A count of thrown-out attempts that is present but unreadable refuses the file.**
///
/// An attempt is disqualified when a skill was used in the run that was meant to be without it; that
/// attempt is never graded. The saved file records how many went that way, and a value that was there but
/// could not be read used to count as none — turning "attempts were thrown out" into "nothing was thrown
/// out", on the number that decides whether a comparison can be trusted at all. Absence still means none,
/// because most entries never carry the field.
@Suite("An unreadable count of thrown-out attempts refuses the file")
struct DisqualifiedCountTests {
    private func saved(_ pollutedField: String) throws -> BenchmarkFile {
        let json = #"""
        {"consistency":{"flaky_eval_ids":[],"k":1,"meaningful":false,"per_eval":[
            {"eval_id":"a","flaky":false,"mean_pass_rate":1,"pass_power_k":1,"perfect_passes":1,"runs":1},
            {"eval_id":"a","arm":"baseline","flaky":false,"mean_pass_rate":0,"pass_power_k":0,
             "perfect_passes":0,"runs":1\#(pollutedField)}],
          "suite_pass_power_k":1},
         "metadata":{"skill_name":"demo","runs_per_configuration":1},
         "runs":[], "run_summary":{}}
        """#
        return try JSONDecoder().decode(BenchmarkFile.self, from: Data(json.utf8))
    }

    @Test("A value that is there and cannot be read refuses the file",
          arguments: [#","polluted":1.5"#, #","polluted":-1"#, #","polluted":"two""#, #","polluted":[]"#])
    func unreadableCountRefused(field: String) throws {
        #expect(throws: EDDError.self) { _ = try RunReport(benchmark: try saved(field)) }
    }

    @Test("No such field still means none were thrown out")
    func absentMeansNone() throws {
        #expect(try RunReport(benchmark: try saved("")).ab?.polluted == 0)
    }

    @Test("A real count is read as itself")
    func realCountRead() throws {
        #expect(try RunReport(benchmark: try saved(#","polluted":2"#)).ab?.polluted == 2)
    }
}
