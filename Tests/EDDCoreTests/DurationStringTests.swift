import Testing
import Foundation
import EDDCore

@Suite("Duration string parsing")
struct DurationStringTests {
    @Test("Parses the config unit suffixes")
    func units() {
        #expect(DurationString.parse("10m") == .seconds(600))
        #expect(DurationString.parse("30s") == .seconds(30))
        #expect(DurationString.parse("1h") == .seconds(3600))
        #expect(DurationString.parse("500ms") == .milliseconds(500))   // ms wins over a trailing s
        #expect(DurationString.parse("45") == .seconds(45))            // bare number → seconds
    }

    @Test("Tolerates whitespace/case; rejects nonsense")
    func edges() {
        #expect(DurationString.parse("  2M ") == .seconds(120))
        #expect(DurationString.parse("abc") == nil)
        #expect(DurationString.parse("") == nil)
        #expect(DurationString.parse("ten m") == nil)
    }
}
