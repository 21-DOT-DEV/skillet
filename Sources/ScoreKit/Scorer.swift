import Foundation
import EDDCore

/// A `[min, max]` quality scale with a "good" direction, ported verbatim from the predecessor
/// (`Scorer.swift`). `normalizedGoodness` maps a raw measurement to `[0, 1]` where `1` is ideal; the
/// runner turns that into the SARIF `level` band + `rank` (§4.2).
public struct ScorerScale: Sendable, Equatable {
    public enum Direction: Sendable, Equatable { case high, low, target(Double) }
    public let min: Double
    public let max: Double
    public let good: Direction
    public init(min: Double, max: Double, good: Direction) { self.min = min; self.max = max; self.good = good }

    /// Normalise a raw measurement to `[0, 1]` goodness (1 = ideal), honouring `good`. A `.target(t)`
    /// scale peaks at `t` and falls off toward either end. Degenerate (zero-span) scales return `1`.
    public func normalizedGoodness(_ value: Double) -> Double {
        let span = max - min
        guard span > 0 else { return 1.0 }
        let t = Swift.max(0, Swift.min(1, (value - min) / span))
        switch good {
        case .high: return t
        case .low: return 1.0 - t
        case let .target(target):
            let distance = abs(value - target)
            let maxDistance = Swift.max(target - min, max - target)
            guard maxDistance > 0 else { return 1.0 }
            return 1.0 - Swift.min(1.0, distance / maxDistance)
        }
    }

    /// The `skillet.scale` property shape: `{ min, max, good, target? }` (the `.target` associated value
    /// lifted to a sibling field so it serializes cleanly).
    var json: JSONValue {
        var o: [String: JSONValue] = ["min": .number(min), "max": .number(max)]
        switch good {
        case .high: o["good"] = .string("high")
        case .low: o["good"] = .string("low")
        case let .target(target): o["good"] = .string("target"); o["target"] = .number(target)
        }
        return .object(o)
    }
}

/// One decoded produced file handed to each scorer (per-file scoring — §4.9).
public struct ScoredFile: Sendable, Equatable {
    public let relativePath: String
    public let text: String
    public init(relativePath: String, text: String) { self.relativePath = relativePath; self.text = text }
}

/// One located match: the text range plus the human message for its finding (the message carries the
/// matched word/phrase for the vocabulary/cutoff checks, or a fixed string otherwise).
public struct Occurrence: Sendable, Equatable {
    public let range: Range<String.Index>
    public let message: String
    public init(range: Range<String.Index>, message: String) { self.range = range; self.message = message }
}

/// What a scorer reports for one file. `.density` → goodness → level/rank + one finding per occurrence
/// (or none if clean). `.categorical` → one fixed-level file-level finding. `.notApplicable` → nothing.
public enum ScorerMeasurement: Sendable {
    /// `denominator` is `nil` for a raw-count check (S005), else the word/sentence count.
    case density(value: Double, denominator: Int?, occurrences: [Occurrence])
    case categorical(level: SarifLevel, message: String)
    case notApplicable
}

/// A deterministic, model-free check over one file's text.
public protocol Scorer: Sendable {
    /// The stable SARIF rule id, e.g. `SKILL-S001`.
    var ruleId: String { get }
    /// The kebab rule name for the catalog, e.g. `slop-vocabulary`.
    var name: String { get }
    /// The ported goodness scale.
    var scale: ScorerScale { get }
    func measure(_ file: ScoredFile, config: SkilletConfig.Scorers) -> ScorerMeasurement
}

/// Turns a text range into a SARIF region with **Unicode-scalar** counts: 1-based line/column, 0-based
/// `charOffset`/`charLength`. A `\r` immediately before a `\n` is treated as part of the line ending
/// (CRLF); a lone `\r` is content.
enum SarifRegionCompute {
    static func region(for range: Range<String.Index>, in text: String) -> SarifRegion {
        let scalars = text.unicodeScalars
        let lower = range.lowerBound.samePosition(in: scalars) ?? scalars.startIndex
        let upper = range.upperBound.samePosition(in: scalars) ?? scalars.endIndex
        let charOffset = scalars.distance(from: scalars.startIndex, to: lower)
        let charLength = scalars.distance(from: lower, to: upper)
        let (startLine, startColumn) = lineColumn(scalars, upTo: lower)
        let (endLine, endColumn) = lineColumn(scalars, upTo: upper)
        return SarifRegion(startLine: startLine, startColumn: startColumn,
                           endLine: endLine, endColumn: endColumn,
                           charOffset: charOffset, charLength: charLength)
    }

    private static func lineColumn(_ scalars: String.UnicodeScalarView, upTo idx: String.UnicodeScalarView.Index) -> (Int, Int) {
        var line = 1, col = 1
        var i = scalars.startIndex
        let newline: Unicode.Scalar = "\n", cr: Unicode.Scalar = "\r"
        while i < idx {
            let s = scalars[i]
            let next = scalars.index(after: i)
            if s == cr, next < scalars.endIndex, scalars[next] == newline {
                // CRLF: the \r is part of the ending — don't count it; the \n resets on the next step.
            } else if s == newline {
                line += 1; col = 1
            } else {
                col += 1
            }
            i = next
        }
        return (line, col)
    }
}
