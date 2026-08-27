import Foundation

/// The machine-readable result of proving an edit by measuring twice (`skillet.iterate/1`).
///
/// **Its own shape, not the one the switched-on-versus-off comparison uses.** The two look alike and
/// will diverge: that one changes when the on/off comparison changes — it counts trials thrown out
/// because a skill fired where it provably could not, a check that cannot fire here because the skill is
/// switched on in both measurements — and this one changes when the edit comparison changes. Sharing a
/// type would couple two features that ship separately, and would publish a number that could only ever
/// be zero under a name describing a check that never ran.
///
/// **What is shared is the statistic**, which must never differ between them:
/// ``PairedDifference/summarize(_:)``.
/// Printed with every verdict: how often the automatic grader agrees with a person has not been
/// measured, so no verdict here is more than provisional.
public let iterateProvisionalNote =
    "provisional until the grader is checked against a person"

public struct IterateReport: SchemaIdentified, Codable, Sendable, Equatable {
    public static let schema = "skillet.iterate/1"

    public let skill: String
    /// The saved draft this proved, and which of its edits were applied.
    public let proposals: String
    public let edits: [Int]
    /// Repeats per test, as observed rather than as requested.
    public let observedK: Int
    /// **The verdict.** True when no test scored lower — which is *not* the same as everything passing.
    public let proven: Bool
    /// Always present, always true for now: how often the automatic grader agrees with a person has not
    /// been measured, so no verdict here is more than provisional.
    public let provisional: Bool
    public let comparison: Comparison
    /// Anything skipped or refused along the way, named with its reason — the "every omission is
    /// disclosed" rule the other reporting commands already follow (``Disclosure``). This command was
    /// the only reporting command with nowhere to put one, which is why a copy that could not be deleted
    /// was left unmentioned in both the printed and the machine-readable result.
    public let disclosures: [Disclosure]
    /// Where the throwaway copy was left, when it was kept — printed for a person, and previously absent
    /// from the machine-readable form, so a script asking to keep the copy was never told where it is.
    public let keptCopy: String?
    /// The command that lands a proven edit. Printed for a person; carried here so a script does not have
    /// to reconstruct it from the parts and get the flags subtly wrong.
    public let landCommand: String?

    /// The second measurement and the paired result. Additive, mirroring how the existing two-arm
    /// report carries its second arm — same idea, own names, because the arms mean different things.
    public struct Comparison: Codable, Sendable, Equatable {
        public let perEval: [Row]
        /// Mean of the per-test differences.
        public let meanDelta: Double
        /// **Absent below two comparable tests** — one difference says nothing about spread, and a
        /// fabricated zero would read as certainty.
        public let standardError: Double?
        public let improved: Int
        public let regressed: Int

        /// The tests that ran on neither side, by name. Empty on every ordinary run. They stay in the
        /// table because a reader needs to see they exist, and stay out of the average because nothing
        /// measured them.
        public var unmeasuredIds: [String] { perEval.filter { !$0.measured }.map(\.id) }
        /// **Whether the average below rests on anything at all.** False when no test ran on either
        /// side — at which point an average change and a spread are arithmetic over nothing, and are
        /// not shown. The measuring command already refuses to state its own headline figure on the
        /// same grounds, in the same words.
        public var anythingMeasured: Bool { perEval.contains(where: \.measured) }

        public struct Row: Codable, Sendable, Equatable {
            public let id: String
            public let beforePasses: Int
            public let beforeRecorded: Int
            public let afterPasses: Int
            public let afterRecorded: Int
            public let delta: Double
            /// This test does not settle to one answer between runs, so part of its difference is
            /// variation. Disclosed, never used to excuse a drop.
            public let noisy: Bool
            /// **Whether anything ran for this test, on either side.** Nothing recorded on both sides is
            /// not a measured change of zero, and the two used to be indistinguishable to anything
            /// reading this. **Derived, never supplied** — the counts beside it already say it, so
            /// accepting it as an argument would only create a way for them to disagree. Same reason
            /// ``IterateReport/observedK`` is derived rather than passed in.
            public let measured: Bool

            public init(id: String, beforePasses: Int, beforeRecorded: Int, afterPasses: Int,
                        afterRecorded: Int, delta: Double, noisy: Bool) {
                self.id = id
                self.beforePasses = beforePasses; self.beforeRecorded = beforeRecorded
                self.afterPasses = afterPasses; self.afterRecorded = afterRecorded
                self.delta = delta; self.noisy = noisy
                self.measured = Self.wasMeasured(before: beforeRecorded, after: afterRecorded)
            }

            /// The one place the rule lives, so building a row and reading one back cannot disagree.
            static func wasMeasured(before: Int, after: Int) -> Bool { before > 0 || after > 0 }

            /// **Read back from the raw counts, never taken from the text.** `measured` says whether this
            /// test ran at all, and it decides whether the test is counted in the average and in the
            /// repeats figure. Left to the generated reader, it was simply taken from the file — so a file
            /// could say a test ran while its own counts said nothing ran, and the two halves of the
            /// report would disagree with each other. Reading a value back is the second place it is
            /// made, and it has to reach the same answer as the first.
            public init(from decoder: Decoder) throws {
                let box = try decoder.container(keyedBy: CodingKeys.self)
                self.id = try box.decode(String.self, forKey: .id)
                self.beforePasses = try box.decode(Int.self, forKey: .beforePasses)
                self.beforeRecorded = try box.decode(Int.self, forKey: .beforeRecorded)
                self.afterPasses = try box.decode(Int.self, forKey: .afterPasses)
                self.afterRecorded = try box.decode(Int.self, forKey: .afterRecorded)
                self.delta = try box.decode(Double.self, forKey: .delta)
                self.noisy = try box.decode(Bool.self, forKey: .noisy)
                self.measured = Self.wasMeasured(before: beforeRecorded, after: afterRecorded)
            }
        }

        public init(perEval: [Row], meanDelta: Double, standardError: Double?, improved: Int, regressed: Int) {
            self.perEval = perEval; self.meanDelta = meanDelta; self.standardError = standardError
            self.improved = improved; self.regressed = regressed
        }
    }

    /// **The repeats cannot be supplied, only derived.** The field says "as observed", and it used to be
    /// handed in — so the requested number was passed instead, and a report claimed three repeats beside
    /// a row that recorded none. Deriving it here makes that impossible to express rather than something
    /// to remember, and matches how the measuring command computes the same-named field: the fewest
    /// repeats any test actually recorded, across both measurements.
    /// **The fewest repeats any test that actually ran recorded, across both measurements.**
    ///
    /// One place, because it is worked out when a report is built and again when one is read back, and
    /// two copies of a rule drifting apart is the defect this project keeps producing.
    static func repeatsObserved(in comparison: Comparison) -> Int {
        comparison.perEval.filter(\.measured)
            .flatMap { [$0.beforeRecorded, $0.afterRecorded] }.min() ?? 0
    }

    /// **Worked out from the rows, never taken from the text.** This figure and the flag on each row are
    /// both described above as derived and not supplied — but the generated reader took them straight from
    /// the file, so a hand-edited or malformed one could state repeats that its own rows contradicted.
    /// Measured before this existed: a report built with nothing recorded said the repeats were none, and
    /// after a single edit to the text it read back as ninety-nine.
    ///
    /// Nothing reads this format back today, which is exactly why it was worth closing now: the next
    /// reader added — a test, a script, a migration — would have inherited the hole silently.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.skill = try box.decode(String.self, forKey: .skill)
        self.proposals = try box.decode(String.self, forKey: .proposals)
        self.edits = try box.decode([Int].self, forKey: .edits)
        self.proven = try box.decode(Bool.self, forKey: .proven)
        self.provisional = try box.decode(Bool.self, forKey: .provisional)
        self.comparison = try box.decode(Comparison.self, forKey: .comparison)
        self.disclosures = try box.decode([Disclosure].self, forKey: .disclosures)
        self.keptCopy = try box.decodeIfPresent(String.self, forKey: .keptCopy)
        self.landCommand = try box.decodeIfPresent(String.self, forKey: .landCommand)
        self.observedK = Self.repeatsObserved(in: comparison)
    }

    public init(skill: String, proposals: String, edits: [Int],
                proven: Bool, provisional: Bool = true, comparison: Comparison,
                disclosures: [Disclosure] = [], keptCopy: String? = nil, landCommand: String? = nil) {
        self.skill = skill; self.proposals = proposals; self.edits = edits
        // **Counted over the tests the average is drawn from, which is the measured ones.** A test that
        // ran on neither side recorded zero repeats, and including it dragged this to zero: measured, one
        // test that ran three times each side, beside one that never ran, printed a real average of
        // `+1.00` next to a claim that the fewest repeats any test recorded was none. The two halves of
        // one line contradicted each other.
        //
        // The tests that ran on neither side are left out of the average already, and named in the
        // omissions list, so nothing is hidden by leaving them out here too — what changes is that this
        // number now describes the same set the figure beside it does. When *no* test ran anywhere this
        // is still zero, and the line then says so instead of stating an average.
        self.observedK = Self.repeatsObserved(in: comparison)
        self.proven = proven; self.provisional = provisional
        self.comparison = comparison; self.disclosures = disclosures
        self.keptCopy = keptCopy
        // Only offered when there is something to land — never beside a blocked verdict.
        self.landCommand = proven ? landCommand : nil
    }
}
