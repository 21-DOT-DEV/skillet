import Testing
@testable import SanitizerKit

@Suite("ExemptMatcher — glob / whole-segment exempt_paths")
struct ExemptMatcherTests {
    @Test("An exact path still matches (backward-compatible with the exact-string behavior)")
    func exact() {
        #expect(ExemptMatcher.isExempt("fixtures/sample.md", patterns: ["fixtures/sample.md"]))
        #expect(!ExemptMatcher.isExempt("fixtures/other.md", patterns: ["fixtures/sample.md"]))
    }

    @Test("`*` globs within one segment and does not cross `/` (the finding's fixtures/*.md case)")
    func starWithinSegment() {
        #expect(ExemptMatcher.isExempt("fixtures/sample.md", patterns: ["fixtures/*.md"]))
        #expect(!ExemptMatcher.isExempt("fixtures/sample.txt", patterns: ["fixtures/*.md"]))
        #expect(!ExemptMatcher.isExempt("fixtures/sub/sample.md", patterns: ["fixtures/*.md"]))  // * stops at /
    }

    @Test("`**` crosses segments")
    func doubleStarCrossesSegments() {
        #expect(ExemptMatcher.isExempt("fixtures/sub/deep.env", patterns: ["**/*.env"]))
        #expect(ExemptMatcher.isExempt("a/b/c.env", patterns: ["**/*.env"]))
    }

    @Test("Leading `**/` matches at the ROOT too (gitignore: zero-or-more leading dirs)")
    func doubleStarPrefixMatchesRoot() {
        #expect(ExemptMatcher.isExempt(".env", patterns: ["**/*.env"]))          // root-level, no leading slash
        #expect(ExemptMatcher.isExempt("config.env", patterns: ["**/*.env"]))
    }

    @Test("`fixtures/**` does NOT overmatch a sibling like `fixturesX` (whole-segment boundary)")
    func doubleStarSuffixRespectsSegmentBoundary() {
        #expect(ExemptMatcher.isExempt("fixtures/secret.txt", patterns: ["fixtures/**"]))   // real subtree matches
        #expect(!ExemptMatcher.isExempt("fixturesX/secret.txt", patterns: ["fixtures/**"])) // sibling must NOT
        #expect(!ExemptMatcher.isExempt("fixturesX", patterns: ["fixtures/**"]))
    }

    @Test("A bare directory name exempts its whole subtree — whole-segment, not substring")
    func directorySubtree() {
        #expect(ExemptMatcher.isExempt("fixtures/sample.md", patterns: ["fixtures"]))
        #expect(ExemptMatcher.isExempt("fixtures/sub/x.md", patterns: ["fixtures/"]))   // trailing slash tolerated
        #expect(!ExemptMatcher.isExempt("fixturesX/y.md", patterns: ["fixtures"]))       // whole-segment: `fixtures` ≠ `fixturesX`
    }

    @Test("Empty pattern set never exempts (default: nothing silenced)")
    func emptyNeverMatches() {
        #expect(!ExemptMatcher.isExempt("anything/at/all.md", patterns: []))
    }

    @Test("Pure-wildcard patterns are flagged over-broad — a blanket bypass the constitution forbids")
    func overBroadFlagged() {
        // Sentinel proof: `**` really would exempt an arbitrary, unrelated path...
        #expect(ExemptMatcher.isExempt("some/unrelated/random.path", patterns: ["**"]))
        // ...so every no-literal-anchor pattern must be flagged.
        for p in ["**", "*", "*/*", "**/*", "**/**"] {
            #expect(ExemptMatcher.isOverBroad(p), "\(p) should be flagged over-broad")
        }
    }

    @Test("Anchored patterns and no-op degenerates are NOT over-broad")
    func anchoredAndNoopsAllowed() {
        for p in ["fixtures/*.md", "fixtures", "fixtures/**", "*.md", "**/*.env", "transcript.md"] {
            #expect(!ExemptMatcher.isOverBroad(p), "\(p) is surgical — should be allowed")
        }
        #expect(!ExemptMatcher.isOverBroad(""))    // empty is a no-op, not a bypass
        #expect(!ExemptMatcher.isOverBroad("/"))
    }
}
