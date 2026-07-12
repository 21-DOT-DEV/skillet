import Testing
import Foundation
@testable import SanitizerKit

@Suite("Finding — betterleaks PascalCase JSON")
struct FindingTests {
    // The real betterleaks 1.6.1 report shape (captured live in the F26/F32 spike). skillet reads only
    // RuleID/Secret/Match/File; the rest is preserved-but-ignored.
    static let realJSON = """
    [
     {
      "RuleID": "github-pat",
      "Description": "Uncovered a GitHub Personal Access Token.",
      "StartLine": 1, "EndLine": 1, "StartColumn": 16, "EndColumn": 55,
      "Match": "ghp_skilletSyntheticCanaryDoNotUse123456",
      "Secret": "ghp_skilletSyntheticCanaryDoNotUse123456",
      "File": "transcript.md",
      "SymlinkFile": "", "Commit": "", "Entropy": 4.68,
      "Fingerprint": "transcript.md:github-pat:1"
     }
    ]
    """

    @Test("Decodes PascalCase RuleID/Secret/Match/File")
    func decodesPascalCase() throws {
        let findings = try JSONDecoder().decode([Finding].self, from: Data(Self.realJSON.utf8))
        #expect(findings.count == 1)
        let f = try #require(findings.first)
        #expect(f.ruleID == "github-pat")
        #expect(f.secret == "ghp_skilletSyntheticCanaryDoNotUse123456")
        #expect(f.match == f.secret)
        #expect(f.file == "transcript.md")
    }

    @Test("Empty array (a clean scan) decodes to no findings")
    func decodesEmpty() throws {
        #expect(try JSONDecoder().decode([Finding].self, from: Data("[]".utf8)).isEmpty)
    }

    @Test("Tolerates a finding missing Match/File (defaults to empty)")
    func tolerantDecode() throws {
        let findings = try JSONDecoder().decode([Finding].self, from: Data(#"[{"RuleID":"aws","Secret":"AKIA1"}]"#.utf8))
        #expect(findings.first?.ruleID == "aws")
        #expect(findings.first?.match == "")
        #expect(findings.first?.file == "")
    }

    // Regression guard for R4-1: the report is PascalCase, NOT the config-DSL's snake_case. If someone
    // "fixes" the CodingKeys back to rule_id/secret, this fails — decoding real output would break.
    @Test("snake_case keys do NOT decode (R4-1 regression guard)")
    func snakeCaseFails() {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode([Finding].self, from: Data(#"[{"rule_id":"aws","secret":"AKIA1"}]"#.utf8))
        }
    }
}
