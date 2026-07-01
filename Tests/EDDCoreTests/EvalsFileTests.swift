import Testing
import Foundation
import EDDCore

@Suite("EvalsFile codec")
struct EvalsFileTests {
    // skill-creator 2.0 object (canonical) — synthetic, modeled on references/schemas.md (not a committed real file).
    let v2 = """
    {"skill_name":"docc-articles","evals":[
      {"id":0,"prompt":"write a tutorial","expected_output":"a .tutorial","files":["a.swift"],"expectations":["has Tutorial","compiles"]},
      {"id":1,"prompt":"fix the article","expected_output":"","expectations":["addresses feedback"]},
      {"id":2,"prompt":"third","expected_output":"","expectations":["x"]}
    ],"viewer_note":"keep me"}
    """
    // legacy bare array
    let legacy = """
    [{"skills":["docc-articles"],"query":"write a tutorial","files":[],"expected_behavior":["has Tutorial","compiles"],"timeout_seconds":600},
     {"skills":["docc-articles"],"query":"second","expected_behavior":["x"]}]
    """

    // Round-trip checks below use *semantic* compare; numeric byte-fidelity (3 vs 3.0) is locked
    // separately in `JSONValueTests.integerFidelity`.
    func decode(_ s: String) throws -> EvalsFile {
        try JSONDecoder().decode(EvalsFile.self, from: Data(s.utf8))
    }

    @Test("Numeric eval ids are exposed as their string form, not dropped (so records keep source ids)")
    func numericIdsCoerced() throws {
        #expect(try decode(v2).cases.map(\.id) == ["0", "1", "2"])
    }

    @Test("Decodes 2.0 object: skill_name, caseCount, normalized case access")
    func decodes2_0() throws {
        let f = try decode(v2)
        #expect(f.skillName == "docc-articles")
        #expect(f.caseCount == 3)
        #expect(!f.isLegacyArray)
        #expect(f.cases[0].prompt == "write a tutorial")
        #expect(f.cases[0].expectations == ["has Tutorial", "compiles"])
        #expect(f.cases[0].files == ["a.swift"])
        #expect(f.cases[0].expectedOutput == "a .tutorial")
    }

    @Test("Decodes legacy array: caseCount + alias normalization (query→prompt, expected_behavior→expectations)")
    func decodesLegacy() throws {
        let f = try decode(legacy)
        #expect(f.skillName == nil)
        #expect(f.caseCount == 2)
        #expect(f.isLegacyArray)
        #expect(f.cases[0].prompt == "write a tutorial")                  // query → prompt
        #expect(f.cases[0].expectations == ["has Tutorial", "compiles"])  // expected_behavior → expectations
    }

    @Test("Local `assertions` alias normalizes to expectations")
    func localAssertions() throws {
        let f = try decode(#"{"skill_name":"x","evals":[{"id":0,"name":"c0","prompt":"p","assertions":["a1","a2"]}]}"#)
        #expect(f.cases[0].expectations == ["a1", "a2"])
    }

    @Test("2.0 round-trips faithfully, preserving unknown top-level + all case keys")
    func roundTrip2_0() throws {
        let f = try decode(v2)
        #expect(f.extra["viewer_note"] == .string("keep me"))
        let out = try JSONEncoder().encode(f)
        #expect(try jsonSemanticEqual(Data(v2.utf8), out))
    }

    @Test("Legacy array round-trips faithfully as an array")
    func roundTripLegacy() throws {
        let out = try JSONEncoder().encode(try decode(legacy))
        #expect(try jsonSemanticEqual(Data(legacy.utf8), out))
    }

    @Test("caseCount is countable for L009 (0, <3, ≥3)")
    func caseCounts() throws {
        #expect(try decode("[]").caseCount == 0)
        #expect(try decode(#"{"skill_name":"x","evals":[{"id":0,"prompt":"p"}]}"#).caseCount == 1)
        #expect(try decode(v2).caseCount == 3)
    }

    @Test("Object without an evals key: caseCount 0, and no `evals` injected on re-emit")
    func objectWithoutEvals() throws {
        let json = #"{"skill_name":"x","note":"draft"}"#
        let f = try decode(json)
        #expect(f.caseCount == 0)
        #expect(!f.isLegacyArray)
        let out = String(decoding: try JSONEncoder().encode(f), as: UTF8.self)
        #expect(!out.contains("evals"))            // not injected — faithful
        #expect(try jsonSemanticEqual(json, out))
    }
}
