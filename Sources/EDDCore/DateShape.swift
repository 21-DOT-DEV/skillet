import Foundation

/// The one `YYYY-MM-DD` validator — shared by `capture --date` and `triage --since`, which had drifted
/// into two hand-rolled twins with the same intent (T11). Shape-exact (rejects a wrong length, a
/// non-digit, or a misplaced dash) **and** calendar-valid: a non-lenient POSIX/UTC formatter rejects an
/// impossible date (`2026-99-99`, `2026-02-30`), so a garbage value can never become a bundle stem or a
/// finding id. Pure/Foundation-only, so it lives in the core and every command reads the same rule.
public enum DateShape {
    public static func isValidISODate(_ s: String) -> Bool {
        let c = Array(s)
        guard c.count == 10 else { return false }
        func digit(_ i: Int) -> Bool { c[i] >= "0" && c[i] <= "9" }
        guard digit(0), digit(1), digit(2), digit(3), c[4] == "-",
              digit(5), digit(6), c[7] == "-", digit(8), digit(9) else { return false }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s) != nil
    }
}
