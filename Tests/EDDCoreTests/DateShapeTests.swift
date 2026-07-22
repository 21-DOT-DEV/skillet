import Testing
@testable import EDDCore

@Suite("DateShape — the shared YYYY-MM-DD validator (T11)")
struct DateShapeTests {
    @Test("Accepts a real ISO date; rejects wrong shape and impossible calendar dates")
    func validation() {
        #expect(DateShape.isValidISODate("2026-07-22"))
        #expect(DateShape.isValidISODate("2024-02-29"))          // real leap day
        // shape failures
        #expect(!DateShape.isValidISODate("2026-7-22"))          // unpadded month
        #expect(!DateShape.isValidISODate("2026/07/22"))         // wrong separator
        #expect(!DateShape.isValidISODate("2026-07-22T00:00"))   // trailing junk
        #expect(!DateShape.isValidISODate(""))
        #expect(!DateShape.isValidISODate("abcd-ef-gh"))
        // calendar failures (shape-valid but impossible)
        #expect(!DateShape.isValidISODate("2026-99-99"))
        #expect(!DateShape.isValidISODate("2026-02-30"))
        #expect(!DateShape.isValidISODate("2025-02-29"))         // 2025 is not a leap year
    }
}
