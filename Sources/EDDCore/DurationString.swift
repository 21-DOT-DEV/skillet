import Foundation

/// Parses skillet's config duration strings (`runs.timeout`, e.g. `"10m"`, `"30s"`, `"500ms"`, `"1h"`)
/// into a `Duration`. Pure (EDDCore) so both the executable's watchdog wiring and its tests share one
/// definition. A bare number is read as seconds; an unrecognized string returns `nil` (the caller
/// falls back to a default rather than failing the run).
public enum DurationString {
    public static func parse(_ string: String) -> Duration? {
        let s = string.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        // `ms` before `s` (a `500ms` value also ends in `s`); `m`/`h` after.
        let units: [(suffix: String, make: (Double) -> Duration)] = [
            ("ms", { .milliseconds(Int($0.rounded())) }),
            ("s", { .seconds($0) }),
            ("m", { .seconds($0 * 60) }),
            ("h", { .seconds($0 * 3600) })
        ]
        for unit in units where s.hasSuffix(unit.suffix) {
            guard let value = Double(s.dropLast(unit.suffix.count)) else { return nil }
            return unit.make(value)
        }
        return Double(s).map { .seconds($0) }   // bare number → seconds
    }
}
