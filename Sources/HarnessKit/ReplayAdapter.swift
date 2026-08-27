import Foundation
import EDDCore
import ProjectKit
import TraceKit

/// An in-memory `HarnessAdapter` for tests — and the proof that the seam is implementable
/// end-to-end with no live harness. Serves a deterministic synthetic `Trace`.
public struct ReplayAdapter: HarnessAdapter {
    public let id: HarnessID = "replay"
    public let capabilities: HarnessCapabilities = [.runTask, .skillInjection, .traceParsing, .baselineIsolation]
    public init() {}

    public func probe(strict: Bool) async throws -> HarnessInfo {
        HarnessInfo(id: id, version: "replay-1", authenticated: true, available: true)
    }

    public func verifySkillVisibility(_ skill: SkillRef, strategy: InjectionStrategy) throws {
        // The replay double "sees" everything — visibility always holds.
    }

    public func verifyBaselineIsolation() async throws {
        // The double is hermetic by construction — its `.none` trace fires no skill (below).
    }

    public func run(_ task: TaskSpec, in workspace: Workspace, skills: SkillSet) async throws -> RawTrace {
        // Arm-aware (F15): a `.none` (baseline) run must serve a skill-free session, or the §9.2
        // pollution tripwire would disqualify every replayed baseline trial.
        if case .none = skills {
            return RawTrace(harness: id, raw: Self.encode(Answer(baseline: true, marker: nil,
                                                                 query: task.query, firedSkills: [])))
        }
        // **The answer reflects the skill it was given.** Without this, two runs of the same tests
        // against *different* versions of a skill produce identical text, so nothing downstream can tell
        // them apart — which makes it impossible to test a command whose whole job is to measure a skill,
        // change it, and measure again. A real run's output does depend on the skill; this is the
        // smallest faithful version of that, and it interprets nothing: a line reading
        // `replay-marker: <text>` in the staged skill is echoed, and anything else is ignored.
        let marker = Self.marker(in: workspace, skill: skills)
        // **Which skills the session says it reached for**, and where that answer comes from.
        //
        // A skill *loaded* into the session was handed over rather than chosen, so it is reported.
        // Nothing loaded means the routing measurement: the whole question is which of the skills on the
        // shelf a model would reach for, and the answer is read from the skills themselves. This used to
        // report a skill named `demo` regardless, so the measurement passed when the skill under test
        // happened to carry that name and failed otherwise, on setups identical in every other way.
        // A stand-in with its answer baked in is defensible only when it serves a single test.
        //
        // **Silence reaches for nothing.** A file that declares nothing is not reached for, because
        // reaching for nothing is a real routing outcome and a silent default is how the old fault got
        // in. This does not make the offline measurement faithful to a real model — no stand-in can be.
        // It makes it faithful to what the fixture stated. Checking it against a real session is `F74`.
        let fired: [String] = {
            // Skills *loaded* into the session were handed over rather than chosen, so they are reported —
            // **all of them**. Only the first used to be named. Every caller in the program hands over
            // exactly one, so nothing was wrong today; but the real thing this stands in for takes as many
            // as it is given (`ClaudeCodeAdapter.swift:150`), so the two disagreed about what the input
            // means, and a second skill would have gone unreported with nothing saying so.
            if case let .only(load, _) = skills, !load.isEmpty { return load.map(\.name) }
            // Everything else is a session choosing for itself — whether a set of skills was named for it
            // or it simply found whatever was staged. Both read the declarations, and both reach for
            // nothing when nothing declares. The second case used to be left out and kept the canned
            // answer, so a session answered as the staged skill while reporting that `demo` had been
            // reached for — a skill that was not there at all.
            return Self.declaredFires(in: workspace, skill: skills)
        }()
        return RawTrace(harness: id, raw: Self.encode(Answer(baseline: false, marker: marker,
                                                             query: task.query, firedSkills: fired,
                                                             tokens: Self.declaredTokens(in: workspace, skill: skills))))
    }

    /// What the stand-in says, before it is turned into a session.
    ///
    /// **Encoded as JSON, decoded by a decoder — no hand-made format.** This used to be written as
    /// `replayed[<marker>]: <query>` and read back by searching for the first `]`, so a marker containing
    /// `]` was cut short: the grader's lookup stopped matching and fell through to a default, which
    /// silently *inverted* a verdict — identical recorded grades blocked a harmful edit with the marker
    /// `v1 release` and declared the same edit proven with `v[1] release`.
    ///
    /// Escaping or length-prefixing would each have repaired that. Using JSON removes the class instead,
    /// and does it by making this stand-in resemble the thing it stands in for: the real adapter already
    /// puts JSON in this same field and reads it back with a decoder (`ClaudeCodeAdapter.swift:183`
    /// and `:134`). A double that needs its own parser is the defect, not the fix — and this one had no
    /// tests of its parser, which is how the bug shipped.
    struct Answer: Codable, Sendable {
        var baseline: Bool
        var marker: String?
        var query: String
        /// **The skills this answer says it reached for.** Without it the canned session always claimed
        /// a skill called `demo` had been reached for, and two measurements grade by asking which skill
        /// that was — so two skills configured identically got opposite results purely from their names:
        /// one called `demo` passed, one called anything else failed. The stand-in has to reflect what it
        /// was handed or told, the same reason it carries the marker above.
        ///
        /// A list, not one name: a session can reach for several skills, and the routing measurement
        /// records the skill under test *and* any other it went to instead. Empty means it reached for
        /// nothing, which is a real answer.
        ///
        /// **Required, so that "says nothing" cannot be expressed.** It used to be optional, and absent
        /// meant "keep whatever the canned session claims" — which for the with-skill canned session is a
        /// skill called `demo`. So any answer that lost this field on the way through reappeared as
        /// `demo`: the give-up text below did exactly that, turning a `tidy-notes` answer into a `demo`
        /// one. Making it required means text lacking it fails to read at all, and unreadable text is
        /// already served as a session that claims nothing.
        var firedSkills: [String]
        /// What the skill's own file said this answer read and wrote, or `nil` when it said nothing.
        /// Nothing is invented: a fixture that wants token counts states them, and one that does not
        /// produces a run where nothing counted — which is the ordinary case and the one that exercises
        /// the results file leaving the entry out.
        var tokens: TokenCounts?
    }

    /// **A fallback must never flip the arm.** This one used to hand back `"baseline":false` whatever it
    /// was given, so a skill-free answer that failed to encode would be read as a with-skill one — and a
    /// with-skill answer in the skill-free arm is exactly what the isolation tripwire disqualifies. It
    /// cannot happen with today's fields, which is the point: a safety net that would invert the arm is
    /// worse than none, because it reads as cover while quietly waiting for a field that can fail.
    static func encode(_ answer: Answer) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]        // deterministic, so recordings compare byte-wise
        guard let data = try? encoder.encode(answer), let text = String(data: data, encoding: .utf8)
        else { return lastResort(for: answer) }
        return text
    }

    /// Named and separate so it can be exercised on its own. Today's fields cannot fail to encode, so
    /// the only way to check that this net does not flip the arm is to call it directly — otherwise the
    /// claim above is untested prose, and the next field added to ``Answer`` decides whether it was true.
    static func lastResort(for answer: Answer) -> String {
        // **It carries everything it can, not just the arm.** It used to emit the arm and nothing else,
        // so the skills the answer reached for were dropped — and a dropped list used to mean "keep the
        // canned answer", which names `demo`. A net that renames the skill under test is worse than no
        // net. Built from the values that cannot fail to write (a flag, some text, a list of text) and
        // assembled by a serializer rather than by hand, so a skill whose name contains a quotation mark
        // cannot break the result — the same reason this stand-in stopped hand-writing its own format.
        var object: [String: Any] = ["baseline": answer.baseline,
                                     "firedSkills": answer.firedSkills,
                                     "query": ""]
        if let marker = answer.marker { object["marker"] = marker }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            // Nothing left that can be trusted to describe the answer, so it claims nothing rather than
            // claiming something wrong. Reaching for nothing is a real answer; reaching for `demo` when
            // the skill is called something else is not.
            return #"{"baseline":\#(answer.baseline),"firedSkills":[],"query":""}"#
        }
        return text
    }

    static func decode(_ raw: String) -> Answer? {
        try? JSONDecoder().decode(Answer.self, from: Data(raw.utf8))
    }

    /// The `replay-marker:` line from the skill this run was **given**, or `nil` when there is none —
    /// which is every existing test, so they see exactly the text they saw before.
    ///
    /// **It reads the named skills, not whatever is on disk.** Listing the staged folder and taking the
    /// first one alphabetically ignored the argument entirely: with two skills staged, every run answered
    /// as the alphabetically-first one, so a test measuring skill `b` silently measured `a`. Loaded
    /// skills are consulted before merely-present ones, matching what a real session would draw on.
    /// **Which skills a session could draw on, resolved once.** Three separate readers — the marker that
    /// tells two versions of a skill apart, the counts of what it read, and which skill it reached for —
    /// each worked this out for themselves, and one of them got a different answer: it ignored the
    /// no-skill-named case entirely, so a session answered *as* the staged skill while reporting that a
    /// skill called `demo` had been reached for, one that was not even there. Resolving it in one place
    /// means a fourth reader cannot repeat that.
    /// **Order matters: the skill under test comes first.** The readers that look for a declaration take
    /// the first file that carries one, so putting the loaded skill ahead of the rest is what stops a
    /// sibling's declaration being read instead of the target's. Named here because it is a guarantee the
    /// callers rely on, not an accident of how two lists were joined.
    ///
    /// **Routing runs have no target to prefer, and that is a real ambiguity.** They stage the whole
    /// corpus with nothing loaded — the question being asked is which skill fires — so if two staged
    /// skills both declare a marker, the alphabetically first wins and nothing says so. Single-declaration
    /// fixtures are the only supported shape; a fixture with two is reading someone else's answer.
    static func candidateNames(in workspace: Workspace, skill: SkillSet) -> [String] {
        switch skill {
        case .none:
            return []
        case let .only(load, visible):
            return (load + visible).map(\.name)
        case .ambient:
            // No skill was named, so there is nothing to prefer — whatever is staged is the whole answer.
            let staged = workspace.root.appendingPathComponent(".claude/skills", isDirectory: true)
            return (try? FileManager.default.contentsOfDirectory(atPath: staged.path))?.sorted() ?? []
        }
    }

    static func marker(in workspace: Workspace, skill: SkillSet) -> String? {
        let staged = workspace.root.appendingPathComponent(".claude/skills", isDirectory: true)
        if case .none = skill { return nil }
        for name in Self.candidateNames(in: workspace, skill: skill) {
            let file = staged.appendingPathComponent("\(name)/SKILL.md")
            // **Read through the one guarded reader, like every other untrusted file in this project.**
            // This was the last unguarded read left in the source, and it was measurably unbounded: it
            // took a 200 MB file in one gulp, once per trial. The guard also checks the path is an
            // ordinary file before opening it — CERT FIO32-C, "do not perform operations on devices that
            // are only appropriate for files", because a path an outsider influenced can point at a
            // device or a pipe, and a read of a pipe can block indefinitely.
            //
            // **Every step of the path is proved, not just the last one.** The plainer reader refuses a
            // shortcut — a file entry that silently points elsewhere — only at the final step, so a
            // shortcut planted on a folder along the way was followed; the comment here used to say it
            // "refuses a link" without that qualification, which claimed more than it did. The gap has a
            // name, `CWE-59` ("link following"). The reader used now proves the whole path from the
            // staged-skills folder down.
            //
            // A refused read is treated exactly as a file with no marker was treated before: skip it.
            // Nothing here is worth failing a measurement over — this stand-in only exists so tests can
            // tell two versions of a skill apart.
            guard case let .success(text) = SafeFile.readConfinedRegularText(file, base: staged, cap: 1 << 20) else { continue }
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("replay-marker:") {
                return line.dropFirst("replay-marker:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// The line a staged skill uses to say it would be reached for. Sibling of `replay-marker:` above,
    /// read the same guarded way, and named so a reader of a fixture can see what it is for.
    static let firesPrefix = "replay-fires:"

    /// **Which of the skills on the shelf say they would be reached for.** The routing answer, taken from
    /// the fixture instead of from a name.
    ///
    /// Read through the one guarded reader, like every other file here that an outsider could influence:
    /// it refuses a link, refuses anything that is not an ordinary file, and caps the size (CERT FIO32-C
    /// — a path someone else chose can point at a device or a pipe, and reading a pipe can block for
    /// ever). A refused read counts as a file that said nothing, which is the same as saying no.
    static func declaredFires(in workspace: Workspace, skill: SkillSet) -> [String] {
        let staged = workspace.root.appendingPathComponent(".claude/skills", isDirectory: true)
        return Self.candidateNames(in: workspace, skill: skill).filter { name in
            let file = staged.appendingPathComponent("\(name)/SKILL.md")
            guard case let .success(text) = SafeFile.readConfinedRegularText(file, base: staged, cap: 1 << 20) else { return false }
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix(Self.firesPrefix) {
                // Only an explicit yes counts. Anything else — `false`, a typo, an empty value — is a
                // file that did not say yes, and a fixture that meant to say yes and did not is a test
                // that fails rather than one that passes for a reason nobody wrote down.
                return line.dropFirst(Self.firesPrefix.count)
                    .trimmingCharacters(in: .whitespaces).lowercased() == "true"
            }
            return false
        }
    }

    /// The line a staged skill uses to state what an answer read and wrote:
    /// `replay-tokens: <uncached> <cache-read> <cache-write> <output>`. Four numbers because the results
    /// file reports four, and a single number could not exercise the difference between them.
    static let tokensPrefix = "replay-tokens:"

    /// **Counts come from the fixture or not at all.** The stand-in cannot know what a model would read,
    /// and guessing would put an invented number where this change has just finished removing one. A
    /// staged skill that says nothing produces an answer that counted nothing — the ordinary case, and
    /// the one that exercises the results file leaving the entry out.
    ///
    /// Read through the one guarded reader, like every other file here an outsider could influence: it
    /// refuses a link, refuses anything that is not an ordinary file, and caps the size. A refused read
    /// counts as a file that said nothing.
    static func declaredTokens(in workspace: Workspace, skill: SkillSet) -> TokenCounts? {
        let staged = workspace.root.appendingPathComponent(".claude/skills", isDirectory: true)
        if case .none = skill { return nil }
        for name in Self.candidateNames(in: workspace, skill: skill) {
            let file = staged.appendingPathComponent("\(name)/SKILL.md")
            guard case let .success(text) = SafeFile.readConfinedRegularText(file, base: staged, cap: 1 << 20) else { continue }
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix(Self.tokensPrefix) {
                let parts = line.dropFirst(Self.tokensPrefix.count)
                    .split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
                // All four or none. A partial line is a fixture that meant something and did not say it,
                // and a test that fails is a better outcome than one that passes on three-quarters of a
                // statement plus a guess at the rest.
                // All four, and all of them a real count. A fixture stating a count below none is a
                // fixture that meant something and did not say it, which takes the same path as one that
                // said only three of the four.
                guard parts.count == 4,
                      let counts = TokenCounts(uncachedInput: parts[0], cacheRead: parts[1],
                                               cacheWrite: parts[2], output: parts[3])
                else { continue }
                return counts
            }
        }
        return nil
    }

    public func parseTrace(_ raw: RawTrace) throws -> Trace {
        // **Unreadable text is served as a skill-free session, not a with-skill one.** Falling back to
        // the with-skill session meant a skill-free answer that failed to parse came back claiming a
        // skill had fired — which the isolation tripwire disqualifies, so a run would report a
        // measurement problem where there was only a parsing one. The skill-free session is the safe
        // reading: it claims nothing.
        guard let answer = Self.decode(raw.raw) else { return Self.cannedBaselineTrace }
        var base = answer.baseline ? Self.cannedBaselineTrace : Self.cannedTrace
        // **The answer always decides, so the canned session's own list never survives.** A run grades on
        // what was reached for; leaving that to a default meant grading on whether the skill happened to
        // be called `demo`. An empty list is an answer — it reached for nothing.
        base.skillInvocations = answer.firedSkills.map { SkillInvocation(skill: $0, turnIndex: 1) }
        // Carry the skill's marker into the answer the grader reads. Without this the marker reaches the
        // raw text and is then thrown away here, so the grader still cannot tell two versions of a skill
        // apart. **Unchanged when there is no marker** — every existing recording sees the same answer it
        // always saw.
        base.usage = answer.tokens
        guard let marker = answer.marker else { return base }
        var carried = base
        carried.turns = base.turns.map { turn in
            guard turn.role == .assistant else { return turn }
            var edited = turn
            edited.text = "\(turn.text) [\(marker)]"
            return edited
        }
        return carried
    }

    /// A small, deterministic synthetic trace (whole-second timestamps so it round-trips exactly).
    ///
    /// **The assistant text below must not contain `[` and must not end with `]`.** The stand-in grader
    /// recovers a skill's marker as the text between the first `" ["` and the final `]`, so a canned
    /// answer carrying either would shift the boundaries and the grader would look up a marker that was
    /// never there — falling back to a default and grading the wrong way round, silently. The rule is
    /// pinned by a test rather than left here to be remembered (`ReplayFramingTests`).
    public static let cannedTrace = Trace(
        harness: "replay",
        harnessVersion: "replay-1",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        endedAt: Date(timeIntervalSince1970: 1_700_000_060),
        turns: [
            Turn(role: .user, text: "do it", at: Date(timeIntervalSince1970: 1_700_000_000)),
            Turn(
                role: .assistant, text: "done",
                toolCalls: [ToolCall(name: "write", input: "out.txt")],
                filesTouched: ["out.txt"],
                at: Date(timeIntervalSince1970: 1_700_000_030)
            )
        ],
        skillInvocations: [SkillInvocation(skill: "demo", turnIndex: 1)],
        workspaceDiff: WorkspaceDiff(added: ["out.txt"]),
        usage: nil
    )

    /// The baseline-arm canned trace (F15): same session shape, **zero skill invocations** — what a
    /// provably skill-free run looks like.
    public static let cannedBaselineTrace = Trace(
        harness: "replay",
        harnessVersion: "replay-1",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        endedAt: Date(timeIntervalSince1970: 1_700_000_060),
        turns: [
            Turn(role: .user, text: "do it", at: Date(timeIntervalSince1970: 1_700_000_000)),
            Turn(
                role: .assistant, text: "done (no skill)",
                toolCalls: [ToolCall(name: "write", input: "out.txt")],
                filesTouched: ["out.txt"],
                at: Date(timeIntervalSince1970: 1_700_000_030)
            )
        ],
        skillInvocations: [],
        workspaceDiff: WorkspaceDiff(added: ["out.txt"]),
        usage: nil
    )
}
