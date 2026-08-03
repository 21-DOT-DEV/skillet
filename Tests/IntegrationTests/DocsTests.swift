import Testing
import Foundation

@Suite("Docs are true", .tags(.integration))
struct DocsTests {
    /// A command the docs claim works today, with its factual contract (exit code, optional `--json` schema).
    struct Claim: Sendable {
        let args: [String]
        let exit: Int32
        var schema: String? = nil
    }

    static let claims: [Claim] = [
        .init(args: ["--help"], exit: 0),
        .init(args: ["--version"], exit: 0),
        .init(args: ["--json"], exit: 0, schema: "skillet.root/1"),
        .init(args: ["-C", "/no/such/x", "--json"], exit: 3, schema: "skillet.error/1"),
        .init(args: ["harness", "list"], exit: 0),
        .init(args: ["harness", "info", "--json"], exit: 0, schema: "skillet.harness-info/1"),
        .init(args: ["doctor", "--help"], exit: 0),
        .init(args: ["lint", "--help"], exit: 0),
        .init(args: ["run", "--help"], exit: 0)
    ]

    @Test("Documented commands hold their exit/JSON contract", arguments: claims)
    func commandHoldsItsClaim(_ claim: Claim) async throws {
        let out = try await SkilletHarness().run(claim.args)
        #expect(out.exitCode == claim.exit)
        if let schema = claim.schema {
            let stream = claim.exit == 0 ? out.stdout : out.stderr
            #expect(stream.contains("\"schema\":\"\(schema)\""))
        }
    }

    @Test("--experimental-dump-help exposes the documented command surface")
    func dumpHelpSurface() async throws {
        let out = try await SkilletHarness().run(["--experimental-dump-help"])
        #expect(out.exitCode == 0)
        // Decoding this minimal shape proves the dump conforms to the expected schema. (The official
        // ArgumentParserToolInfo models are a target, not an exposed product, so we use a local type.)
        struct Dump: Decodable {
            struct Command: Decodable { let commandName: String?; let subcommands: [Command]? }
            let command: Command
        }
        let dump = try JSONDecoder().decode(Dump.self, from: Data(out.stdout.utf8))
        let names = (dump.command.subcommands ?? []).compactMap(\.commandName)
        #expect(names.contains("init"))
        #expect(names.contains("doctor"))
        #expect(names.contains("lint"))
        #expect(names.contains("run"))
    }

    @Test("Internal documentation links resolve")
    func internalDocLinksResolve() throws {
        for doc in ["README.md", "AGENTS.md", "ROADMAP.md"] {
            let text = try DocFile.read(doc)
            for link in DocFile.internalLinks(in: text) {
                #expect(
                    FileManager.default.fileExists(atPath: DocFile.root.appending(path: link).path),
                    "broken link \(link) in \(doc)"
                )
            }
        }
    }

    // MARK: - status restatements must agree with their source

    /// The status **label** only — the leading word or two, before any date, dash or explanation.
    /// Scanning the whole cell was wrong: one plan's status prose reads "Planned across eight review
    /// rounds, then built test-first", which made a shipped feature look planned.
    static func statusToken(_ cell: some StringProtocol) -> String {
        var token = cell.replacingOccurrences(of: "*", with: "")
        for terminator in ["—", "(", ",", ";", " - ", ":"] {
            if let cut = token.range(of: terminator) { token = String(token[token.startIndex..<cut.lowerBound]) }
        }
        // Drop leading decoration — three plans write "✅ IMPLEMENTED". The label is the word, not the
        // ornament, and matching on a prefix means an emoji would otherwise make a status unreadable.
        let cleaned = token.drop(while: { !$0.isLetter })
        return cleaned.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Whether a status label means "there is working code behind this".
    /// `nil` for a word neither list knows — surfaced by the callers rather than silently passing, so a
    /// new status vocabulary gets a deliberate decision instead of an unnoticed hole in the check.
    static func claimsShipped(_ token: String) -> Bool? {
        for planned in ["planned", "future", "proposed", "draft", "not started"] where token.hasPrefix(planned) {
            return false
        }
        for shipped in ["implemented", "landed", "complete", "in progress", "shipped", "audit complete"]
        where token.hasPrefix(shipped) { return true }
        return nil
    }

    /// Two consecutive features shipped while these documents still called them planned. A feature's
    /// own plan is the authority for its status; the index restates it so there is one place to scan.
    /// A restatement that has to exist is a restatement worth checking.
    @Test("The feature index agrees with each feature's own plan about whether it shipped")
    func specIndexAgreesWithEachPlan() throws {
        let index = try DocFile.read("Specs/README.md")
        let specs = DocFile.root.appending(path: "Specs")
        let folders = try FileManager.default.contentsOfDirectory(atPath: specs.path)
            .filter { $0.first?.isNumber == true }.sorted()
        #expect(folders.count > 5, "guard against the check silently finding nothing to compare")

        for folder in folders {
            let planPath = "Specs/\(folder)/plan.md"
            guard let plan = try? DocFile.read(planPath) else { continue }
            // The plan's own status row: `| **Status** | ... |`
            guard let row = plan.split(separator: "\n").first(where: { $0.contains("**Status**") }) else { continue }
            let planCells = row.split(separator: "|", omittingEmptySubsequences: false)
            guard planCells.count >= 3, let planShipped = Self.claimsShipped(Self.statusToken(planCells[2])) else {
                Issue.record("unrecognised status in \(planPath): \(row.prefix(60))"); continue
            }

            // The index row for the same number, e.g. `| 018 | ... | Implemented (…) | … |`
            let number = String(folder.prefix(3))
            guard let indexRow = index.split(separator: "\n")
                .first(where: { $0.hasPrefix("| \(number) |") }) else {
                Issue.record("no index row in Specs/README.md for \(folder)"); continue
            }
            let cells = indexRow.split(separator: "|", omittingEmptySubsequences: false)
            guard cells.count >= 5, let indexShipped = Self.claimsShipped(Self.statusToken(cells[4])) else {
                Issue.record("unrecognised index status for \(folder)"); continue
            }
            #expect(indexShipped == planShipped,
                    "Specs/README.md disagrees with \(planPath) about whether \(folder) shipped")
        }
    }

    /// The roadmap's phase table restates each phase document's status. Same rule, one level up.
    @Test("The roadmap's phase table agrees with each phase document")
    func roadmapAgreesWithPhaseDocuments() throws {
        let roadmap = try DocFile.read("ROADMAP.md")
        let dir = DocFile.root.appending(path: "Roadmap")
        let phaseDocs = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("phase-") && $0.hasSuffix(".md") && !$0.contains("review") }.sorted()
        #expect(phaseDocs.count > 5, "guard against the check silently finding nothing to compare")

        for name in phaseDocs {
            let text = try String(contentsOf: dir.appending(path: name), encoding: .utf8)
            guard let statusLine = text.split(separator: "\n").first(where: { $0.hasPrefix("**Status:**") })
            else { Issue.record("\(name) has no status line"); continue }
            let label = statusLine.replacingOccurrences(of: "**Status:**", with: "")
            guard let docShipped = Self.claimsShipped(Self.statusToken(label)) else {
                Issue.record("unrecognised status in \(name): \(statusLine.prefix(60))"); continue
            }

            let number = name.dropFirst("phase-".count).prefix(while: \.isNumber)
            guard let tableRow = roadmap.split(separator: "\n")
                .first(where: { $0.hasPrefix("|") && $0.contains("| \(number) |") }) else {
                Issue.record("no phase-table row in ROADMAP.md for \(name)"); continue
            }
            let cells = tableRow.split(separator: "|", omittingEmptySubsequences: false)
            guard cells.count >= 5, let tableShipped = Self.claimsShipped(Self.statusToken(cells[4])) else {
                Issue.record("unrecognised phase-table status for \(name)"); continue
            }
            #expect(tableShipped == docShipped,
                    "ROADMAP.md's phase table disagrees with Roadmap/\(name)")
        }
    }

    /// A phase document's header status, computed from its own feature rows.
    ///
    /// The header used to *restate* which features had shipped — "IN PROGRESS (F3 + F14 shipped …)" —
    /// a hand-maintained copy of the rows a few lines below it. It drifted in both directions: two
    /// documents said a feature had shipped while its row still said planned, and one had a shipped row
    /// its header never mentioned. The roll-up is gone, so the header carries only the status word, and
    /// that word is now checkable against the rows rather than trusted.
    enum PhaseRoll { case complete, inProgress, notStarted }

    static func rollUp(ofRowsIn text: String) -> PhaseRoll? {
        var shipped = 0, pending = 0
        for line in text.split(separator: "\n") where line.contains("**[F") && line.contains("]**") {
            guard line.first?.isNumber == true else { continue }
            // **The LAST dash, not the first.** Several feature titles contain a dash of their own
            // ("Corpus triage — Track A"), so splitting on the first one reads a title as a status.
            guard let lastDash = line.range(of: "—", options: .backwards) else { continue }
            let token = Self.statusToken(line[lastDash.upperBound...])
            if token.hasPrefix("implemented") || token.hasPrefix("done") || token.hasPrefix("shipped") {
                shipped += 1
            } else if token.hasPrefix("planned") || token.hasPrefix("future") {
                pending += 1
            }
        }
        if shipped == 0 && pending == 0 { return nil }        // nothing to compare
        if pending == 0 { return .complete }
        return shipped == 0 ? .notStarted : .inProgress
    }

    @Test("Each phase document's status word matches what its own feature rows say")
    func phaseHeaderMatchesItsOwnRows() throws {
        let dir = DocFile.root.appending(path: "Roadmap")
        let docs = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("phase-") && $0.hasSuffix(".md") && !$0.contains("review") }.sorted()
        #expect(docs.count > 5, "guard against the check silently finding nothing to compare")

        var compared = 0
        for name in docs {
            let text = try String(contentsOf: dir.appending(path: name), encoding: .utf8)
            guard let rolled = Self.rollUp(ofRowsIn: text) else { continue }
            guard let statusLine = text.split(separator: "\n").first(where: { $0.hasPrefix("**Status:**") })
            else { Issue.record("\(name) has no status line"); continue }
            let header = Self.statusToken(statusLine.replacingOccurrences(of: "**Status:**", with: ""))

            let expected: PhaseRoll
            if header.hasPrefix("complete") || header.hasPrefix("done") { expected = .complete }
            else if header.hasPrefix("in progress") { expected = .inProgress }
            else if header.hasPrefix("planned") || header.hasPrefix("future") { expected = .notStarted }
            else { Issue.record("unrecognised phase status in \(name): \(header)"); continue }

            compared += 1
            #expect(rolled == expected,
                    "Roadmap/\(name) says '\(header)' but its feature rows say \(rolled)")
        }
        #expect(compared > 5, "every phase document with feature rows should have been compared")
    }

    /// The reverse of the check above, which only ever confirmed that *documented* commands exist.
    /// Nothing required the opposite — so a command could ship, work, and never be written down, which
    /// is exactly what happened. The binary is the source of truth here and cannot drift.
    @Test("Every command the binary exposes is documented in the contributor guide")
    func everyShippedCommandIsDocumented() async throws {
        let out = try await SkilletHarness().run(["--experimental-dump-help"])
        struct Dump: Decodable {
            struct Command: Decodable { let commandName: String?; let subcommands: [Command]? }
            let command: Command
        }
        let dump = try JSONDecoder().decode(Dump.self, from: Data(out.stdout.utf8))
        let names = (dump.command.subcommands ?? []).compactMap(\.commandName)
            .filter { $0 != "help" }        // supplied by the parser, not ours to document
        #expect(names.count > 5, "guard against the check silently finding nothing to compare")

        let guideText = try DocFile.read("AGENTS.md")
        // The Commands section only — a passing mention elsewhere in the file is not documentation.
        guard let start = guideText.range(of: "## Commands (true now") else {
            Issue.record("AGENTS.md has no Commands section"); return
        }
        let rest = guideText[start.upperBound...]
        let section = String(rest[..<(rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex)])
        for name in names {
            #expect(section.contains("skillet \(name)"),
                    "`skillet \(name)` ships but is not documented in AGENTS.md's Commands section")
        }
    }
}
