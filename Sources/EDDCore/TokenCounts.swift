import Foundation

/// **How many tokens a model read and wrote, for one attempt.**
///
/// A *token* is the unit a model charges and reasons in — roughly a word-piece. Providers report several
/// counts, not one, because some of the input may be served from the provider's own cache: a store it
/// keeps so that repeating part of a request costs less than sending it fresh.
///
/// **The naming here is deliberate, and the reason is a real and repeated bug.** Two conventions publish
/// a field called `input_tokens` with opposite meanings. Anthropic's API uses it for the input that was
/// *not* cached; the OpenTelemetry telemetry convention uses it for the whole input, cached or not.
/// Systems that map the first onto the second and then add the cache counts on top report roughly double
/// the real figure — filed against Langfuse as issue 12306 and confirmed there as the consumer's fault
/// rather than the producer's, because both conventions were behaving as documented. So no field here is
/// called `inputTokens`. Each is named for exactly what it holds, and the roll-up is called
/// ``TokenCounts/total``.
///
/// **Present or absent, never partly filled.** A provider that reports usage reports all of these, using
/// zero for a kind that did not occur; one that reports none leaves the whole value absent. There is
/// therefore no way to express "some counts but not others", which is what would otherwise make the
/// roll-up quietly mean different things on different runs.
public struct TokenCounts: Codable, Sendable, Equatable {
    /// Input sent fresh — not served from, and not written to, the provider's cache.
    public let uncachedInput: Int
    /// Input served from the provider's cache. Read cheaply, but the model still read it.
    public let cacheRead: Int
    /// Input written into the provider's cache by this request, so a later one can reuse it.
    public let cacheWrite: Int
    /// Tokens the model produced.
    public let output: Int

    /// **Everything the model read and wrote.** The figure that means the same thing whether the cache
    /// was warm or cold, which is what makes two runs comparable: a run that happened to hit a warm cache
    /// did not thereby read less. **Derived, never supplied** — it cannot disagree with its parts.
    public var total: Int { uncachedInput + cacheRead + cacheWrite + output }

    /// **The largest count that survives being written down.** These numbers are written into the saved
    /// results file as JSON, where a number is held as a double, and above this value a whole number
    /// silently changes on the way through: measured, `9007199254740993` is written and reads back as
    /// `9007199254740992`. The JSON standard names this exact range as the one where every reader agrees
    /// on the value, so a count above it is one this tool cannot honestly record.
    ///
    /// **It also removes a way the program could stop dead.** Adding four of these up used to be able to
    /// exceed what a whole number holds, which halts the program rather than wrapping around — measured,
    /// a run declaring counts near that ceiling parked while writing them out and never returned, leaving
    /// nothing behind. Four values below this ceiling cannot come close, so that stall cannot happen.
    ///
    /// Real use is nowhere near: a thousand tests, a hundred repeats each, every one filling a full
    /// million-token context, comes to about ninety-thousandth of this.
    public static let largestExact = (1 << 53) - 1

    /// **A count below none is refused here rather than checked later.** These are counts of things a
    /// model read and wrote; none of them can be negative. Left unchecked, one arriving from a provider's
    /// reply or from a test fixture would flow into the totals and averages written into the saved
    /// results file, where a negative total is not a quantity anything can act on.
    ///
    /// Settled where the value is made, so it holds everywhere the value appears rather than at whichever
    /// call sites remembered to check — including ``init(from:)`` below, which reads one back from a file
    /// and is the second place a value is made. It answers "no" rather than explaining why: the two places
    /// that build one from a tool's output discard an unusable statement without wanting a reason, and the
    /// reader, which does want one, has the four numbers in hand and can say which was impossible.
    public init?(uncachedInput: Int, cacheRead: Int = 0, cacheWrite: Int = 0, output: Int) {
        guard uncachedInput >= 0, cacheRead >= 0, cacheWrite >= 0, output >= 0 else { return nil }
        // **The sum is added up in a way that reports going over rather than stopping the program.**
        // Written plainly, this line is only safe because the ceiling below happens to be small enough
        // that four of them cannot overflow — so the check guarding against a halt could itself halt, and
        // would do so the moment anyone raised the ceiling. Measured: with the ceiling at the largest
        // whole number, this line stopped a test process dead rather than failing it. Asking for the
        // overflow instead of risking it removes that dependence on a number declared elsewhere.
        let (readSoFar, over1) = uncachedInput.addingReportingOverflow(cacheRead)
        let (readTotal, over2) = readSoFar.addingReportingOverflow(cacheWrite)
        let (everything, over3) = readTotal.addingReportingOverflow(output)
        // Every part is at least none, so the whole being within range puts each part within it too.
        guard !over1, !over2, !over3, everything <= Self.largestExact else { return nil }
        self.uncachedInput = uncachedInput; self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite; self.output = output
    }

    /// Adding two attempts' counts gives the counts for both — used to total a session whose turns are
    /// each reported separately. Every turn genuinely read what it reports, including the context it
    /// re-sent, which is the same basis a provider bills on.
    /// **One vocabulary for these four numbers, wherever they are written.** The diagnostic file a run
    /// leaves behind and the saved results file are read side by side when something looks wrong, and
    /// they used to name the same quantities differently — `cache_read` in one, `input_cache_read_tokens`
    /// in the other — so a reader comparing them had to know they meant the same thing. Both now write
    /// these names, and a test compares the two rather than trusting them to stay aligned.
    ///
    /// **The names are spelled in the form the encoders convert *from*.** Both files are written with
    /// automatic camel-to-underscore conversion and read with the reverse, so a key written here already
    /// in underscore form would encode correctly and then fail to decode — the reader converts the
    /// incoming name to camel form before matching it. Spelling them this way is what makes both
    /// directions work.
    enum CodingKeys: String, CodingKey {
        case uncachedInput = "inputUncachedTokens"
        case cacheRead = "inputCacheReadTokens"
        case cacheWrite = "inputCacheWriteTokens"
        case output = "outputTokens"
        case total = "totalTokens"
    }

    /// **The roll-up is written, but never read back.** Written because a reader of a file should not
    /// have to add up four numbers whose correct summing is the exact thing that trips people up; not
    /// read because it is derived, so a file whose stated roll-up disagrees with its own parts is
    /// resolved in favour of the parts rather than believed.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(uncachedInput, forKey: .uncachedInput)
        try box.encode(cacheRead, forKey: .cacheRead)
        try box.encode(cacheWrite, forKey: .cacheWrite)
        try box.encode(output, forKey: .output)
        try box.encode(total, forKey: .total)
    }

    /// **Reading one back from a file is the other place a value is made, so the same refusal belongs
    /// here.** A count below none was refused by the constructor above and then accepted straight back in
    /// through this one, so the type could hold — by way of a file — a value it would not let anyone write
    /// in code. That is the long-standing rule that reading an object back is a second constructor and has
    /// to establish every invariant the first one does; a reader that skips the check is the documented
    /// way an otherwise-careful type ends up in a state it forbids.
    ///
    /// **The rule is not restated here.** This hands the four numbers to the constructor above and reports
    /// its refusal, rather than repeating "not below none" in a second place that could later disagree
    /// with the first — the failure this file has already been corrected for several times. The numbers
    /// are looked at again only to say *which* one was impossible.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let uncachedInput = try box.decode(Int.self, forKey: .uncachedInput)
        let cacheRead = try box.decode(Int.self, forKey: .cacheRead)
        let cacheWrite = try box.decode(Int.self, forKey: .cacheWrite)
        let output = try box.decode(Int.self, forKey: .output)
        guard let counts = TokenCounts(uncachedInput: uncachedInput, cacheRead: cacheRead,
                                       cacheWrite: cacheWrite, output: output) else {
            let impossible = [(CodingKeys.uncachedInput, uncachedInput), (.cacheRead, cacheRead),
                              (.cacheWrite, cacheWrite), (.output, output)].first { $0.1 < 0 }
            throw DecodingError.dataCorrupted(.init(
                // The container's own path, and the field named in the message in the spelling the file
                // uses — the coding names here are the camel form the reader converts *to*, so putting one
                // in the path would point at a name that does not appear in the file.
                codingPath: box.codingPath,
                debugDescription: impossible.map {
                    "\(Self.jsonName($0.0)) is \($0.1), and a count of what a model read or wrote cannot "
                        + "be below none"
                } ?? "these are not possible token counts"))
        }
        self = counts
    }

    /// The same five entries, as raw values — for the saved results file, which is assembled by hand
    /// rather than through the machinery above. Sourced from the same names so the two cannot drift.
    public var jsonObject: [String: JSONValue] {
        [
            Self.jsonName(.total): .number(Double(total)),
            Self.jsonName(.uncachedInput): .number(Double(uncachedInput)),
            Self.jsonName(.cacheRead): .number(Double(cacheRead)),
            Self.jsonName(.cacheWrite): .number(Double(cacheWrite)),
            Self.jsonName(.output): .number(Double(output))
        ]
    }

    /// A coding name in the underscore form it is written as — the conversion the encoders apply.
    private static func jsonName(_ key: CodingKeys) -> String {
        var out = ""
        for character in key.rawValue {
            if character.isUppercase { out += "_" + character.lowercased() } else { out.append(character) }
        }
        return out
    }

    /// **Adding can produce a total too large to write down, so it can answer "no".** Its comment used to
    /// say a refusal here would make every caller handle something that cannot happen. That was true of
    /// counts below none — it is not true of counts too large to record, because two totals that are each
    /// within range can add to one that is not. The same rule as the constructor, in the second place a
    /// value is made, rather than a different rule beside it.
    ///
    /// Each part is within range, so the four sums below cannot overflow on the way to being checked.
    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts? {
        TokenCounts(uncachedInput: lhs.uncachedInput + rhs.uncachedInput,
                    cacheRead: lhs.cacheRead + rhs.cacheRead,
                    cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
                    output: lhs.output + rhs.output)
    }
}
