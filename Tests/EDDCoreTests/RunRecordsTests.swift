import Testing
import Foundation
import EDDCore

/// Synthetic fixtures modeled on skill-creator 2.0 `references/schemas.md` (not committed real files).
@Suite("Run-record family codecs")
struct RunRecordsTests {
    // Round-trips via *semantic* compare (1 == 1.0). Numeric byte-fidelity (3 vs 3.0) is locked
    // separately in `JSONValueTests.integerFidelity` — these checks intentionally don't re-cover it.
    func roundTrips<T: RawJSONObject>(_ type: T.Type, _ json: String) throws -> T {
        let value = try JSONDecoder().decode(T.self, from: Data(json.utf8))
        let out = try JSONEncoder().encode(value)
        #expect(try jsonSemanticEqual(Data(json.utf8), out), "\(T.self) did not round-trip faithfully")
        return value
    }

    @Test("benchmark.json: accessors + faithful round-trip (viewer keys + unknown preserved)")
    func benchmark() throws {
        let json = """
        {"metadata":{"skill_name":"docc-articles","skill_path":"skills/docc-articles","executor_model":"claude","timestamp":"2026-05-19T00:00:00Z","evals_run":3,"runs_per_configuration":3,"analyzer_model":"claude"},
         "runs":[{"configuration":"with_skill","eval_id":0,"result":{"pass_rate":0.94,"passed":3,"failed":0,"total":3,"time_seconds":12.0,"tokens":1000,"errors":0,"tool_calls":4}}],
         "run_summary":{"default":{"pass_rate":0.94}},"notes":["stabilize first"]}
        """
        let b = try roundTrips(BenchmarkFile.self, json)
        #expect(b.skillName == "docc-articles")
        #expect(b.runs.count == 1)
        #expect(b.notes == ["stabilize first"])
        #expect(b.runs[0].objectValue?["result"]?.objectValue?["pass_rate"] == .number(0.94))  // nesting under result
        #expect(b.metadata?["analyzer_model"] == .string("claude"))  // local extra field preserved
    }

    @Test("benchmark.json round-trips the real skill-creator shape (default arm + consistency + per-run expectations)")
    func benchmarkRealShape() throws {
        // Modeled on a real skill-creator 2.0 artifact (consistency block + configuration:"default" +
        // per-run expectation results). Synthetic — real artifacts are read-only and never committed (VI).
        let json = """
        {"consistency":{"flaky_eval_ids":[],"k":1,"meaningful":false,"per_eval":[{"eval_id":0,"flaky":false,"mean_pass_rate":1,"pass_power_k":1,"perfect_passes":1,"runs":1}],"suite_pass_power_k":1},
         "metadata":{"skill_name":"demo","runs_per_configuration":1,"evals_run":[0]},
         "runs":[{"configuration":"default","eval_id":0,"run_number":1,"expectations":[{"text":"t","passed":true,"evidence":"e"}],"result":{"pass_rate":1.0,"passed":1,"total":1}}],
         "run_summary":{"default":{"pass_rate":{"max":1,"mean":1,"min":1,"stddev":0}}}}
        """
        let b = try roundTrips(BenchmarkFile.self, json)
        #expect(b.runs[0].objectValue?["configuration"] == .string("default"))
        #expect(b.fields["consistency"]?.objectValue?["suite_pass_power_k"] == .number(1))
        #expect(try RunReport(benchmark: b).evals.first?.id == "0")   // recompute reads consistency + coerces numeric id
    }

    @Test("grading.json: text/passed/evidence + summary; round-trip")
    func grading() throws {
        let json = """
        {"expectations":[{"text":"compiles","passed":true,"evidence":"built ok"},{"text":"has Tutorial","passed":false,"evidence":"missing"}],
         "summary":{"passed":1,"failed":1,"total":2,"pass_rate":0.5},
         "execution_metrics":{},"timing":{},"claims":[],"user_notes_summary":{},"eval_feedback":{}}
        """
        let g = try roundTrips(GradingFile.self, json)
        #expect(g.passRate == 0.5)
        #expect(g.passed == 1)
        #expect(g.total == 2)
        #expect(g.expectations[0].objectValue?["text"] == .string("compiles"))
        #expect(g.expectations[0].objectValue?["passed"] == .bool(true))
        #expect(g.expectations[0].objectValue?["evidence"] == .string("built ok"))
    }

    @Test("timing / metrics / eval_metadata: accessors + round-trip + unknown-key preservation")
    func smallRecords() throws {
        let t = try roundTrips(TimingFile.self, #"{"total_tokens":1000,"duration_ms":12000,"total_duration_seconds":12.0,"future":1}"#)
        #expect(t.totalTokens == 1000)
        #expect(t.durationMs == 12000)
        #expect(t.fields["future"] == .number(1))  // unknown key survived

        let m = try roundTrips(MetricsFile.self, #"{"tool_calls":{"Read":3,"Write":1},"total_tool_calls":4,"total_steps":5,"files_created":["a.txt"],"errors_encountered":0,"output_chars":100,"transcript_chars":200}"#)
        #expect(m.totalSteps == 5)
        #expect(m.filesCreated == ["a.txt"])
        #expect(m.toolCalls?["Read"] == .number(3))

        let e = try roundTrips(EvalMetadataFile.self, #"{"name":"case-0","assertions":["a1","a2"]}"#)
        #expect(e.name == "case-0")
        #expect(e.assertions == ["a1", "a2"])
    }

    @Test("A non-object document is rejected, not crashed")
    func rejectsNonObject() {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(BenchmarkFile.self, from: Data("[1,2,3]".utf8))
        }
    }
}

/// **Rewriting the saved results must not delete what this version does not recognise.**
///
/// The file is documented as keeping anything it does not understand, so that a field written by a newer
/// version of this tool survives being rewritten by an older one. It did the opposite: rewriting built a
/// fresh document from only the fields it knew about, and everything else vanished — measured, a field at
/// the top level and a field inside the settings block were both handed in and both discarded. Building a
/// new object out of the fields you understand is the named way this kind of data gets lost.
///
/// Nothing caught it because the existing round-trip test only covers reading a file and writing it back
/// unchanged. Nothing covered *rewriting* one, which is the path that loses data.
@Suite("Rewriting keeps what this version does not recognise")
struct RewritePreservesUnknownFieldsTests {
    private let provenance = RunProvenance(judgeProvider: "p", judgeModel: "m",
                                           judgePromptVersion: "v", executorBinaryVersion: "x")
    private func rewrite(over prior: BenchmarkFile) throws -> BenchmarkFile {
        let v = Verdict(criterion: "c", passed: true, rationale: "", judgeId: "t", model: "m", judgePromptVersion: "1")
        let arm = [EvalResult(evalId: "a", trials: [TrialResult(exit: .passed, verdicts: [v])])]
        return try BenchmarkFile(
            skill: "demo",
            behavioral: (report: try RunReport(skill: "demo", results: arm), evals: arm),
            baseline: nil, trigger: nil, harness: "replay", k: 1,
            provenance: provenance, preserving: prior)
    }

    @Test("A field this version knows nothing about survives, wherever it sits")
    func unknownFieldsSurvive() throws {
        let prior = BenchmarkFile(fields: [
            "future_top_level": .string("written by a newer version"),
            "metadata": .object(["future_setting": .string("also newer"), "skill_name": .string("demo")]),
            "consistency": .object(["future_figure": .number(7)]),
            "run_summary": .object(["future_summary": .bool(true)])
        ])
        let written = try rewrite(over: prior)
        #expect(written.fields["future_top_level"] == .string("written by a newer version"))
        #expect(written.metadata?["future_setting"] == .string("also newer"),
                "a field inside a section is exactly the case that was lost")
        #expect(written.fields["consistency"]?.objectValue?["future_figure"] == .number(7))
        #expect(written.fields["run_summary"]?.objectValue?["future_summary"] == .bool(true))
    }

    /// The other half: this version's own figures must win, not be shadowed by what was there before.
    @Test("A field this version does own takes the new value")
    func knownFieldsAreOverwritten() throws {
        let prior = BenchmarkFile(fields: ["metadata": .object(["skill_name": .string("stale-name")])])
        let written = try rewrite(over: prior)
        #expect(written.metadata?["skill_name"] == .string("demo"), "the run being written decides this")
    }

    /// Attempts are a list, and a position in a list identifies nothing to merge with — so they are
    /// replaced whole, which is the standard rule and also the only correct one here: a carried-over
    /// entry would report an attempt that did not happen.
    @Test("The recorded attempts are this run's, not the previous run's")
    func attemptsAreReplacedNotMerged() throws {
        let prior = BenchmarkFile(fields: ["runs": .array([.object(["configuration": .string("ancient")])])])
        let written = try rewrite(over: prior)
        let configurations = (written.fields["runs"]?.arrayValue ?? [])
            .compactMap { $0.objectValue?["configuration"]?.stringValue }
        #expect(!configurations.contains("ancient"), "an attempt that did not happen must not be reported")
        #expect(!configurations.isEmpty, "and this run's attempts are there")
    }
}
