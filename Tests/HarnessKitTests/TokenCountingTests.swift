import Testing
import Foundation
import EDDCore
import TraceKit
import HarnessKit

/// **Reading how many tokens a run used, without double-counting them.**
///
/// A *token* is the unit a model charges and reasons in. The tool that runs the model reports several
/// counts per reply, not one, because part of the input may be served from the provider's cache — a store
/// it keeps so repeating part of a request costs less than sending it fresh.
///
/// The trap these tests exist for: two published conventions use the name `input_tokens` for opposite
/// quantities. This provider means "the input that was *not* cached"; the widely-used telemetry
/// convention means "the whole input, cached or not". Adding the cache counts on top of a figure that
/// already includes them roughly doubles the answer — filed against one observability tool as issue
/// 12306, where real numbers were 5 fresh tokens, 128,955 read from cache and 1,253 written to it, and
/// the displayed total was about twice the truth.
@Suite("Token counts are read per kind, never summed onto an already-summed field")
struct TokenCountingTests {
    /// One reply, shaped like the real session files this parser reads.
    private func reply(uncached: Int, cacheRead: Int, cacheWrite: Int, output: Int) -> String {
        """
        {"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"assistant",\
        "content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":\(uncached),\
        "cache_read_input_tokens":\(cacheRead),"cache_creation_input_tokens":\(cacheWrite),\
        "output_tokens":\(output)}}}
        """
    }

    private func parse(_ jsonl: String) throws -> Trace {
        try ClaudeCodeAdapter().parseTrace(RawTrace(harness: "claude-code", raw: jsonl))
    }

    /// The exact numbers from the filed bug. Getting this wrong reports about twice the real figure.
    @Test("Each kind is read from its own field, so nothing is counted twice")
    func eachKindReadSeparately() throws {
        let counts = try #require(try parse(reply(uncached: 5, cacheRead: 128_955,
                                                  cacheWrite: 1_253, output: 100)).usage)
        #expect(counts.uncachedInput == 5)
        #expect(counts.cacheRead == 128_955)
        #expect(counts.cacheWrite == 1_253)
        #expect(counts.output == 100)
        #expect(counts.total == 130_313, "5 + 128,955 + 1,253 + 100 — each counted once")
    }

    /// A session is many replies, and each one genuinely read what it reports, including any context it
    /// re-sent. Adding them is what the provider bills on.
    @Test("A session with several replies reports what all of them read and wrote")
    func repliesAddUp() throws {
        let session = [reply(uncached: 10, cacheRead: 20, cacheWrite: 30, output: 40),
                       reply(uncached: 1, cacheRead: 2, cacheWrite: 3, output: 4)].joined(separator: "\n")
        let counts = try #require(try parse(session).usage)
        #expect(counts.uncachedInput == 11)
        #expect(counts.cacheRead == 22)
        #expect(counts.cacheWrite == 33)
        #expect(counts.output == 44)
        #expect(counts.total == 110)
    }

    /// **Nothing counted means nothing claimed.** A session whose lines carry no counts must not come
    /// back reporting zeros — a zero reads as an observation, and this is the absence of one.
    @Test("A session that reports no counts reports nothing, not zeros")
    func absentMeansAbsent() throws {
        let line = """
        {"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"assistant",\
        "content":[{"type":"text","text":"ok"}]}}
        """
        #expect(try parse(line).usage == nil)
    }

    /// **A reply that reports only some of its counts poisons the whole session.** Substituting zero for
    /// a missing one turns a half-reported reply into a confident under-count; keeping the other replies
    /// and dropping this one makes the session total short while looking complete. Neither is honest, and
    /// an under-count that looks whole is the worse of the two, because nothing about it reads as wrong.
    ///
    /// Unreachable against every session on this machine — all 10,833 replies carry all four counts —
    /// which is why it is enforced rather than described: an invariant the code does not check is prose,
    /// and the next change to what a provider sends decides whether it was ever true.
    @Test("A reply reporting only some of its counts makes the session report none",
          arguments: [#""input_tokens":5,"output_tokens":10"#,
                      #""input_tokens":5,"cache_read_input_tokens":1,"output_tokens":10"#,
                      #""output_tokens":10"#,
                      #""input_tokens":"five","cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":10"#])
    func partialReplyReportsNothing(usage: String) throws {
        let head = #"{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"#
        #expect(try parse(head + usage + "}}}").usage == nil)
    }

    /// **Losing a number must not lose a reply.** The automatic grader reads the conversation, so a reply
    /// that disappears can turn a pass into a failure — and nothing anywhere would record that a line had
    /// gone missing. Abandoning the counting used to skip past the code that adds the reply to the
    /// conversation as well, so an unreadable number cost the whole reply.
    @Test("A reply whose counts cannot be read still appears in the conversation")
    func unreadableCountsKeepTheReply() throws {
        let good = #"{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"first"}],"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}}"#
        let partial = #"{"type":"assistant","timestamp":"2026-01-01T00:00:01.000Z","message":{"role":"assistant","content":[{"type":"text","text":"the answer"}],"usage":{"output_tokens":10}}}"#
        let trace = try parse([good, partial].joined(separator: "\n"))
        let said = trace.turns.filter { $0.role == .assistant }.map(\.text)
        #expect(said == ["first", "the answer"],
                "the grader reads these — a missing one changes the verdict with nothing saying why")
        #expect(trace.usage == nil, "and the counts are still abandoned, which is the part that was right")
    }

    @Test("One unreadable reply discards the counts of the readable ones alongside it")
    func oneBadReplyPoisonsTheSession() throws {
        let bad = #"{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"output_tokens":10}}}"#
        let session = [reply(uncached: 10, cacheRead: 20, cacheWrite: 30, output: 40), bad]
            .joined(separator: "\n")
        #expect(try parse(session).usage == nil,
                "the total would be short, and a short total presented as whole is the fault being avoided")
    }

    /// **Only the model's own replies are counted.** Both kinds of line become part of the conversation,
    /// and both used to be read for counts. Tokens spent on a result handed back from a tool are already
    /// inside the *next* reply's input figure — that is what the model then reads — so a count appearing
    /// on the person's line could only be those same tokens stated a second time, and adding it would
    /// roughly double the total. Measured across every session on this machine, no line other than a
    /// model reply carries a count block at all, so this cannot happen today.
    @Test("A count on a line that is not the model's reply is ignored, not added on top")
    func onlyModelRepliesAreCounted() throws {
        let modelReply = reply(uncached: 10, cacheRead: 20, cacheWrite: 30, output: 40)
        let personLine = #"{"type":"user","timestamp":"2026-01-01T00:00:01.000Z","message":{"role":"user","content":[{"type":"text","text":"go on"}],"usage":{"input_tokens":999,"cache_read_input_tokens":999,"cache_creation_input_tokens":999,"output_tokens":999}}}"#
        let counts = try #require(try parse([modelReply, personLine].joined(separator: "\n")).usage)
        #expect(counts.total == 100, "10 + 20 + 30 + 40 — the other line's figures are not added on top")
    }

    /// The person's line still becomes part of the conversation; only its counts are ignored.
    @Test("Ignoring a line's counts does not drop the line from the conversation")
    func ignoringCountsKeepsTheLine() throws {
        let modelReply = reply(uncached: 1, cacheRead: 1, cacheWrite: 1, output: 1)
        let personLine = #"{"type":"user","timestamp":"2026-01-01T00:00:01.000Z","message":{"role":"user","content":[{"type":"text","text":"go on"}],"usage":{"input_tokens":999,"cache_read_input_tokens":999,"cache_creation_input_tokens":999,"output_tokens":999}}}"#
        let trace = try parse([modelReply, personLine].joined(separator: "\n"))
        #expect(trace.turns.contains { $0.text == "go on" })
    }

    /// **A session saved with Windows line endings is read, not silently discarded.**
    ///
    /// This does not degrade line by line, which is what makes it dangerous: in Swift a carriage return
    /// followed by a newline is a *single* character, so asking to split on a newline never matches it and
    /// the entire file arrives as one piece that is not valid on its own. Measured before the fix: a
    /// two-reply session came back with no conversation at all and no counts. The automatic grader then
    /// reads an empty conversation and fails every expectation — a measured failure produced by how a file
    /// was saved, with nothing anywhere saying so.
    ///
    /// A single-line file happens to survive either way, because trailing blank space is tolerated around
    /// a lone value — which is exactly why a test would have to use more than one line to catch this.
    @Test("A session with Windows line endings is read the same as one without")
    func windowsLineEndingsAreRead() throws {
        let session = [reply(uncached: 1, cacheRead: 2, cacheWrite: 3, output: 4),
                       reply(uncached: 10, cacheRead: 20, cacheWrite: 30, output: 40)].joined(separator: "\n")
        let windows = session.replacingOccurrences(of: "\n", with: "\r\n")

        let plain = try parse(session)
        let saved = try parse(windows)
        #expect(saved.turns.count == plain.turns.count, "the whole conversation must survive, not vanish")
        #expect(saved.turns.map(\.text) == plain.turns.map(\.text))
        #expect(saved.usage?.total == plain.usage?.total, "and so must what it cost")
        #expect(plain.turns.count == 2, "two replies went in, so two must come out")
    }

    /// A kind that did not occur is reported as zero by the provider and is a real zero — distinct from
    /// the whole thing being absent.
    @Test("A run that used no cache reports zero for it, and still reports a total")
    func zeroCacheIsAMeasurement() throws {
        let counts = try #require(try parse(reply(uncached: 500, cacheRead: 0,
                                                  cacheWrite: 0, output: 250)).usage)
        #expect(counts.cacheRead == 0)
        #expect(counts.total == 750)
    }
}

/// The offline substitute answers instead of a real model so tests cost nothing. It cannot know what a
/// model would read, so it states what the fixture told it and nothing otherwise — inventing a number
/// here would put back the made-up figure this change removed.
@Suite("The offline substitute reports only the counts its fixture states")
struct DeclaredTokenTests {
    private func stage(_ declaration: String?) throws -> (Workspace, SkillRef) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-tokens-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent(".claude/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: demo\n---\n\(declaration.map { $0 + "\n" } ?? "")Body.\n"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return (Workspace(root: root), SkillRef(name: "demo", path: dir.path))
    }

    private func counted(_ declaration: String?) async throws -> TokenCounts? {
        let (workspace, ref) = try stage(declaration)
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: .only(load: [ref]))
        return try adapter.parseTrace(raw).usage
    }

    @Test("A stated set of counts is what the answer reports")
    func statedCountsAreReported() async throws {
        let counts = try #require(try await counted("replay-tokens: 100 900 50 200"))
        #expect(counts.uncachedInput == 100)
        #expect(counts.cacheRead == 900)
        #expect(counts.cacheWrite == 50)
        #expect(counts.output == 200)
        #expect(counts.total == 1250)
    }

    @Test("A fixture that states nothing produces a run that counted nothing")
    func silenceCountsNothing() async throws {
        #expect(try await counted(nil) == nil, "the ordinary case — and the one that must not invent a zero")
    }

    /// **All four or none.** A half-written line is a fixture that meant something and did not say it;
    /// failing is a better outcome than passing on three-quarters of a statement plus a guess.
    @Test("A partial or unreadable statement counts as no statement",
          arguments: ["replay-tokens: 100 900 50", "replay-tokens:", "replay-tokens: a b c d",
                      "replay-tokens: 1 2 3 4 5"])
    func partialStatementIgnored(line: String) async throws {
        #expect(try await counted(line) == nil)
    }

    @Test("A run deliberately without the skill counts nothing, whatever any file says")
    func skillFreeRunCountsNothing() async throws {
        let (workspace, _) = try stage("replay-tokens: 100 900 50 200")
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let adapter = ReplayAdapter()
        let raw = try await adapter.run(TaskSpec(query: "q"), in: workspace, skills: SkillSet.none)
        #expect(try adapter.parseTrace(raw).usage == nil)
    }
}

/// **"Nobody said" and "somebody said something unusable" must not look the same.**
///
/// When a reply reports what it cost but the figures cannot be trusted — a field missing, a number below
/// none — the whole session's counts are discarded on purpose, so a half-read figure never enters a total.
/// But a session that reported nothing at all is *also* recorded as no counts. Both come out as an absent
/// entry, so nothing anywhere distinguishes "this run cost nothing to report" from "this run reported its
/// cost and we could not read it" — and the second is a problem someone would want to know about.
///
/// Same shape as the reason an attempt was never graded, which used to be discarded and is now recorded.
@Suite("An unusable cost report is distinguishable from no report at all")
struct UsageStateTests {
    private func parsed(_ jsonl: String) throws -> Trace {
        try ClaudeCodeAdapter().parseTrace(RawTrace(harness: "claude-code", raw: jsonl))
    }
    private let head = #"{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]"#

    @Test("A reply that says nothing about cost is recorded as having said nothing")
    func silenceIsRecordedAsSilence() throws {
        let trace = try parsed(head + "}}")
        #expect(trace.usage == nil)
        #expect(trace.usageState == .absent, "no figures were offered, which is not a fault")
    }

    @Test("A reply whose cost figures cannot be read is recorded as such")
    func unusableFiguresAreRecordedAsUnusable() throws {
        let trace = try parsed(head + #","usage":{"output_tokens":10}}}"#)
        #expect(trace.usage == nil, "a part-read figure must never enter a total")
        #expect(trace.usageState == .unreadable, "but the run must be able to say why the figure is missing")
    }

    @Test("A reply with complete figures is recorded as counted")
    func completeFiguresAreCounted() throws {
        let usage = #","usage":{"input_tokens":1,"cache_read_input_tokens":2,"cache_creation_input_tokens":3,"output_tokens":4}}}"#
        let trace = try parsed(head + usage)
        #expect(trace.usage?.total == 10)
        #expect(trace.usageState == .counted)
    }
}
