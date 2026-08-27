import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

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

    /// **What a run tells you to do next names only verbs that exist.** The list is filtered against the
    /// binary rather than written down, so an unshipped verb is never suggested and a shipped one needs
    /// no edit. Both halves are pinned here: `iterate` ships and must appear; `next` does not and must
    /// not — and when it does ship, this test is what says so out loud rather than letting the suggestion
    /// change unnoticed.
    @Test("A run suggests only loop verbs the tool answers to")
    func suggestionsNameOnlyRealCommands() async throws {
        let registered = try await Self.registeredCommands()
        #expect(registered.contains("iterate"), "shipped, so it must be suggestable")
        #expect(!registered.contains("next"),
                "`next` has shipped, so a run now suggests it — intended behaviour; update this expectation deliberately rather than deleting it")

        let root = try Fixture.makeRunRepo(); defer { Fixture.remove(root) }
        let out = try await SkilletHarness().run(["-C", root.path, "run", "demo", "--replay", "--yes"])
        #expect(out.stdout.contains("skillet iterate"), "the shipped verb is offered")
        #expect(!out.stdout.contains("skillet next"), "an unshipped verb is never offered")
    }

    /// The names the binary actually answers to.
    static func registeredCommands() async throws -> Set<String> {
        let out = try await SkilletHarness().run(["--experimental-dump-help"])
        struct Dump: Decodable {
            struct Command: Decodable { let commandName: String?; let subcommands: [Command]? }
            let command: Command
        }
        let names = (try JSONDecoder().decode(Dump.self, from: Data(out.stdout.utf8))
            .command.subcommands ?? []).compactMap(\.commandName).filter { $0 != "help" }
        #expect(names.count > 5, "guard against the check silently finding nothing to compare")
        return Set(names)
    }

    /// The reverse of the two checks above, and the direction that was missing. They prove every shipped
    /// command is written down; neither notices the design document **presenting a command you cannot
    /// run** — which it did for two of them, alongside a list of options the parser rejects. Anything
    /// named there but not registered has to be marked, in the document, with the marker below; the
    /// marker is what turns "this looks out of date" into something a machine settles.
    static let plannedMarker = "(planned)"

    /// **The contributor guide's list of commands is checked against what the tool answers to.**
    ///
    /// That page listed nine commands as available which the tool refuses — a reader learning from it was
    /// sent to verbs that do not exist. The design document has carried the same list correctly, with the
    /// unshipped ones marked, and a test enforcing it; the guide duplicated the list without either. A
    /// duplicated list with only one of them checked is a list that drifts.
    @Test("The contributor guide lists nothing you cannot run, unless it says so")
    func guideListsNothingYouCannotRun() async throws {
        let registered = try await Self.registeredCommands()
        let guide = try DocFile.read("AGENTS.md")
        // **Only the "answers today" half is checked.** The other half declares itself planned, so its
        // names are supposed to be absent from the tool. Checking line by line instead was useless: the
        // heading and the entries share a line, so every entry inherited the word "planned" from the
        // heading and nothing could ever fail — caught by undoing the fix and watching the test pass.
        guard let available = guide.range(of: "**Answers today:**"),
              let planned = guide.range(of: "**Planned, not yet accepted:**",
                                        range: available.upperBound..<guide.endIndex) else {
            Issue.record("AGENTS.md no longer separates what the tool answers to from what is planned")
            return
        }
        let claimed = String(guide[available.upperBound..<planned.lowerBound])

        var checked = 0
        for (offset, phrase) in claimed.split(separator: "`", omittingEmptySubsequences: false).enumerated()
        where offset % 2 == 1 {
            guard let name = phrase.split(separator: " ").first.map(String.init),
                  name.allSatisfy(\.isLetter) else { continue }
            checked += 1
            #expect(registered.contains(name),
                    "`\(name)` is listed as something the tool answers to today, and it does not")
        }
        #expect(checked > 0, "the check found nothing to verify, which means it is not reading the section")
    }

    @Test("Every command the design document lists is one the tool answers to, or is marked planned")
    func designListsNothingYouCannotRun() async throws {
        let registered = try await Self.registeredCommands()
        let design = try DocFile.read("skillet-design.md")
        guard let block = Self.porcelainBlock(design) else {
            Issue.record("skillet-design.md has no porcelain command block to check"); return
        }
        var checked = 0
        for line in block.split(separator: "\n") {
            let text = String(line)
            guard let name = text.split(separator: " ").dropFirst().first.map(String.init),
                  text.hasPrefix("skillet ") else { continue }
            checked += 1
            if registered.contains(name) {
                #expect(!text.contains(Self.plannedMarker),
                        "`skillet \(name)` ships — remove the \(Self.plannedMarker) marker")
            } else {
                #expect(text.contains(Self.plannedMarker),
                        "the design document presents `skillet \(name)` as something you can run, but the tool does not register it — mark it \(Self.plannedMarker)")
            }
        }
        #expect(checked > 5, "guard against the check silently finding nothing to compare")
    }

    /// The design document's usage line for `suggest` advertised two options the parser refuses, so a
    /// reader following it got a parse error. Same rule as above, applied to option names.
    ///
    /// **Every documented command, not one of them.** This check was written for `suggest` alone, and
    /// the gap showed: the proving command's usage line was corrected when it shipped while the sentence
    /// directly beneath it still spelled the flag that had just been replaced, through a full green
    /// suite. Anything with a `#### \`skillet <name>\`` block is compared, so a command cannot be
    /// documented with flags the tool refuses just because nobody thought to extend the check.
    static let commandsWithSynopsis = ["suggest", "iterate"]

    @Test("Every option the design document spells out is one the parser accepts",
          arguments: DocsTests.commandsWithSynopsis)
    func designSpellsOnlyRealOptions(command: String) async throws {
        let accepted = try await Self.acceptedOptions(of: command)
        let design = try DocFile.read("skillet-design.md")
        guard let synopsis = Self.synopsis(design, for: command) else {
            Issue.record("skillet-design.md has no `skillet \(command)` usage block to check"); return
        }
        // Everything that looks like an option in the usage line, and the planned ones listed beneath it.
        let named = Set(synopsis.matches(of: /--[a-z][a-z-]+/).map { String($0.output) })
        let planned = Set(Self.plannedOptions(design, for: command))
        #expect(!named.isEmpty, "guard against the check silently finding nothing to compare")
        for option in named.subtracting(planned) {
            #expect(accepted.contains(option),
                    "the design document spells `\(option)` in the \(command) usage line, but the parser does not accept it — either ship it or list it as planned beneath the block")
        }
        for option in planned where accepted.contains(option) {
            Issue.record("`\(option)` is listed as planned for \(command) but the parser now accepts it — move it into the usage line")
        }
    }

    /// **The contributor guide names options too, and nothing was comparing them.** Its command-surface
    /// list gives each command with the switches that distinguish it, and it said the proving command
    /// takes `--apply` when that command takes `--edits` — while a line sixty rows earlier in the same
    /// file spelled it correctly. Anyone reading that list to learn the tool would have been sent to a
    /// switch the parser refuses. The design document had this check; the guide people are pointed at
    /// first did not.
    @Test("Every option the contributor guide's command list names is one the parser accepts")
    func guideSurfaceSpellsOnlyRealOptions() async throws {
        let guide = try DocFile.read("AGENTS.md")
        guard let heading = guide.range(of: "### Command surface") else {
            Issue.record("AGENTS.md has no command-surface list to check"); return
        }
        let rest = guide[heading.upperBound...]
        let block = String(rest[..<(rest.range(of: "\n###")?.lowerBound ?? rest.endIndex)])

        // Only commands the tool answers to today. The list is forward-looking on purpose, so a name it
        // does not yet register is not an error — and asking about one would trip the shared lookup's own
        // guard, which reports an unregistered name rather than returning nothing.
        let registered = try await Self.registeredCommands()

        var checked = 0
        for match in block.matches(of: /`([a-z][a-z ]*)`\s*\n?\s*\(([^)]*)\)/) {
            let command = String(match.output.1).trimmingCharacters(in: .whitespaces)
            guard registered.contains(command) else { continue }

            // Each backticked entry inside the brackets, keeping only those that are a switch and nothing
            // else. `which --search` is skipped because that switch belongs to a nested command, not to
            // this one, and comparing it here would report a fault that is not there. A `†` marks a
            // switch listed as planned rather than shipped, exactly as the design document marks its own.
            let named = String(match.output.2).matches(of: /`([^`]+)`/).map { String($0.output.1) }
            let options = named.filter { $0.hasPrefix("--") && !$0.contains(" ") && !$0.hasSuffix("†") }
            guard !options.isEmpty else { continue }

            let accepted = try await Self.acceptedOptions(of: command)
            checked += 1
            for option in options {
                #expect(accepted.contains(option),
                        "AGENTS.md's command list says `\(command)` takes `\(option)`, which the parser refuses")
            }
        }
        #expect(checked >= 3, "guard against the check silently finding nothing to compare")
    }

    /// The reverse blind spot: the usage line is only the *headline*. A flag the parser refuses can sit
    /// in the prose under it and no check notices — which is exactly what happened, and what this pins.
    /// Scoped to the paragraphs before the next heading, and only to spellings that look like flags.
    @Test("No prose under a command's usage line spells an option the parser refuses",
          arguments: DocsTests.commandsWithSynopsis)
    func designProseSpellsOnlyRealOptions(command: String) async throws {
        let accepted = try await Self.acceptedOptions(of: command)
        let design = try DocFile.read("skillet-design.md")
        guard let prose = Self.prose(design, for: command) else {
            Issue.record("skillet-design.md has no `skillet \(command)` section to check"); return
        }
        let planned = Set(Self.plannedOptions(design, for: command))
        let named = Set(prose.matches(of: /--[a-z][a-z-]+/).map { String($0.output) })
        #expect(!named.isEmpty, "guard against the check silently finding nothing to compare")
        for option in named.subtracting(planned) where !accepted.contains(option) {
            Issue.record("the `skillet \(command)` section describes `\(option)`, but the parser does not accept it — correct the prose, or mark it planned beneath the usage block")
        }
    }

    /// The long option names a command **accepts**, read from the parser's own structured dump.
    ///
    /// **Not `--help`'s text.** Matching against the help *output* silently passes a flag the command
    /// merely mentions: this command's help names `suggest --apply` when telling you how to land a
    /// proven edit, so a check reading the text would accept `--apply` as one of *its* flags — which is
    /// exactly the stale spelling this pair exists to catch. Found by undoing the fix and watching the
    /// check pass anyway.
    static func acceptedOptions(of command: String) async throws -> Set<String> {
        struct Dump: Decodable {
            struct Name: Decodable { let kind: String; let name: String }
            struct Argument: Decodable { let names: [Name]? }
            struct Command: Decodable {
                let commandName: String?
                let subcommands: [Command]?
                let arguments: [Argument]?
            }
            let command: Command
        }
        let out = try await SkilletHarness().run(["--experimental-dump-help"])
        let dump = try JSONDecoder().decode(Dump.self, from: Data(out.stdout.utf8))
        guard let match = (dump.command.subcommands ?? []).first(where: { $0.commandName == command })
        else {
            Issue.record("`skillet \(command)` is not a registered command"); return []
        }
        let names = Set((match.arguments ?? [])
            .flatMap { $0.names ?? [] }
            .filter { $0.kind == "long" }
            .map { "--" + $0.name })
        #expect(names.count > 3, "guard against the check silently finding nothing to compare")
        return names
    }

    /// The fenced block under "porcelain" in §6.1 — the list a reader takes as "what I can run".
    static func porcelainBlock(_ design: String) -> String? {
        guard let anchor = design.range(of: "skillet init        # adopt skillet in a repo") else { return nil }
        let rest = design[anchor.lowerBound...]
        return String(rest[..<(rest.range(of: "\n```")?.lowerBound ?? rest.endIndex)])
    }

    /// The fenced usage line under a `#### \`skillet <name>\`` heading.
    static func synopsis(_ design: String, for command: String) -> String? {
        guard let section = section(design, for: command) else { return nil }
        guard let open = section.range(of: "```") else { return nil }
        let body = section[open.upperBound...]
        return String(body[..<(body.range(of: "```")?.lowerBound ?? body.endIndex)])
    }

    /// Everything under a command's heading, up to the next `####` — its own section and no other's.
    static func section(_ design: String, for command: String) -> String? {
        guard let heading = design.range(of: "#### `skillet \(command)`") else { return nil }
        let rest = design[heading.upperBound...]
        return String(rest[..<(rest.range(of: "\n#### ")?.lowerBound ?? rest.endIndex)])
    }

    /// A command's section with its fenced blocks removed — the running text a reader takes as a claim
    /// about what the tool accepts. Sample *output* lives in fences and is not a claim about flags.
    static func prose(_ design: String, for command: String) -> String? {
        guard let section = section(design, for: command) else { return nil }
        return section.components(separatedBy: "```").enumerated()
            .filter { $0.offset.isMultiple(of: 2) }.map(\.element).joined(separator: "\n")
    }

    /// Options the design document itself declares not-yet-available, read from the line beneath the
    /// usage block so the exemption lives next to the claim it exempts.
    static func plannedOptions(_ design: String, for command: String) -> [String] {
        guard let section = section(design, for: command) else { return [] }
        let window = String(section.prefix(2_000))
        guard let line = window.range(of: "Planned, not yet accepted:") else { return [] }
        let tail = window[line.upperBound...]
        let sentence = String(tail[..<(tail.range(of: "\n\n")?.lowerBound ?? tail.endIndex)])
        return sentence.matches(of: /--[a-z][a-z-]+/).map { String($0.output) }
    }

    // MARK: - the documentation catalog

    static let catalog = DocFile.root.appending(path: "Sources/skillet/skillet.docc")

    static func catalogFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: catalog.path).filter { $0.hasSuffix(".md") }
    }

    /// The catalog listed four commands while nine shipped, and nothing noticed. The binary is the
    /// source of truth and cannot drift.
    @Test("Every command the binary exposes appears in the documentation's command table")
    func catalogListsEveryCommand() async throws {
        let out = try await SkilletHarness().run(["--experimental-dump-help"])
        struct Dump: Decodable {
            struct Command: Decodable { let commandName: String?; let subcommands: [Command]? }
            let command: Command
        }
        let names = (try JSONDecoder().decode(Dump.self, from: Data(out.stdout.utf8))
            .command.subcommands ?? []).compactMap(\.commandName).filter { $0 != "help" }
        #expect(names.count > 5, "guard against the check silently finding nothing to compare")

        let landing = try String(contentsOf: Self.catalog.appending(path: "skillet.md"), encoding: .utf8)
        for name in names {
            #expect(landing.contains("| `\(name)` |"),
                    "`skillet \(name)` ships but has no row in the documentation's command table")
        }
    }

    @Test("Every cross-reference in the documentation points at a document that exists")
    func catalogCrossReferencesResolve() throws {
        let files = try Self.catalogFiles()
        #expect(files.count > 1)
        let stems = Set(files.map { String($0.dropLast(3)) })
        for file in files {
            let text = try String(contentsOf: Self.catalog.appending(path: file), encoding: .utf8)
            for match in text.components(separatedBy: "<doc:").dropFirst() {
                let target = String(match.prefix(while: { $0 != ">" }))
                #expect(stems.contains(target), "\(file) links to <doc:\(target)>, which does not exist")
            }
        }
    }

    /// **The tutorial is a test, output included.** Its shell steps are extracted and executed in a
    /// scratch folder, in order, and each step's printed output is compared **exactly** against the
    /// sample shown beneath it — the model Go bakes in for documentation examples, where the declared
    /// output is the assertion. Checking only that commands succeed was half the job: it caught a step
    /// that stopped working, but not a sample that had drifted from what the tool prints.
    ///
    /// Exact comparison is sustainable here because nothing in these samples varies between runs — no
    /// dates, no generated identifiers, no absolute paths. Churn is what trains people to re-record a
    /// snapshot without reading it, and there is none to churn.
    ///
    /// The convention: ```sh fences are the tour and are run; a ```text fence immediately after one is
    /// that step's expected output. A step with no sample beneath it is only required to succeed.
    /// Machine-specific setup is written as prose so it can never be mistaken for either.
    @Test("The free tutorial's commands still work, and print what it says they print", .tags(.slow))
    func tutorialCommandsStillWork() async throws {
        let text = try String(contentsOf: Self.catalog.appending(path: "TryingItForFree.md"), encoding: .utf8)

        // Fenced blocks in order, so each command can be paired with the sample beneath it.
        var fences: [(kind: String, body: String)] = []
        var current: [Substring]?
        var kind = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```sh") { current = []; kind = "sh"; continue }
            if line.hasPrefix("```text") { current = []; kind = "text"; continue }
            if line.hasPrefix("```"), current != nil {
                fences.append((kind, current!.joined(separator: "\n"))); current = nil; continue
            }
            if current != nil { current!.append(line) }
        }
        var steps: [(command: String, sample: String?)] = []
        for (index, fence) in fences.enumerated() where fence.kind == "sh" {
            let next = index + 1 < fences.count ? fences[index + 1] : nil
            steps.append((fence.body, next?.kind == "text" ? next?.body : nil))
        }
        #expect(steps.count >= 5, "found \(steps.count) runnable steps — the tour should have more")
        #expect(steps.contains { $0.sample != nil }, "no step has a sample to compare against")

        // One shell, so the working directory and created files carry across steps; a marker between
        // them splits the combined output back apart. Errors are folded into the same stream so the
        // comparison sees what a person at a terminal would see, in the order they would see it.
        let marker = "===SKILLET-DOC-STEP==="
        let script = (["exec 2>&1", "set -e"] + steps.enumerated().map { index, step in
            (index == 0 ? "" : "printf '\\n\(marker)\\n'\n") + step.command
        }).joined(separator: "\n")

        let scratch = try Fixture.makeTempDirectory(); defer { Fixture.remove(scratch) }
        let binDirectory = try SkilletHarness().executable.removingLastComponent()
        let path = "\(binDirectory):" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")

        let result = try await Subprocess.run(
            .path(FilePath("/bin/sh")),
            arguments: .init(["-c", script]),
            environment: .inherit.updating(["PATH": path]),
            workingDirectory: FilePath(scratch.path),
            output: .string(limit: 1 << 20), error: .string(limit: 1 << 20))
        var code: Int32 = -1
        if case let .exited(value) = result.terminationStatus { code = value }
        let printed = result.standardOutput ?? ""
        #expect(code == 0, "a command in the tutorial failed:\n\(printed)")

        // Only surrounding blank lines are normalised — a sample must otherwise match to the character.
        let actual = printed.components(separatedBy: "\n\(marker)\n")
        #expect(actual.count == steps.count, "expected \(steps.count) steps of output, got \(actual.count)")
        for (index, step) in steps.enumerated() where step.sample != nil {
            guard index < actual.count else { continue }
            let expected = step.sample!.trimmingCharacters(in: .newlines)
            let got = actual[index].trimmingCharacters(in: .newlines)
            #expect(got == expected, """
                the tutorial shows different output than the command produces, at step \(index + 1):
                --- the tutorial says ---
                \(expected)
                --- the command printed ---
                \(got)
                """)
        }
    }
}
