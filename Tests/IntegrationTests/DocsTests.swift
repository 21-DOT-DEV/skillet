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
    @Test("Every option the design document spells out for suggest is one the parser accepts")
    func designSpellsOnlyRealOptions() async throws {
        let help = try await SkilletHarness().run(["suggest", "--help"]).stdout
        let design = try DocFile.read("skillet-design.md")
        guard let synopsis = Self.suggestSynopsis(design) else {
            Issue.record("skillet-design.md has no `skillet suggest` usage block to check"); return
        }
        // Everything that looks like an option in the usage line, and the planned ones listed beneath it.
        let named = Set(synopsis.matches(of: /--[a-z][a-z-]+/).map { String($0.output) })
        let planned = Set(Self.plannedOptions(design))
        #expect(!named.isEmpty, "guard against the check silently finding nothing to compare")
        for option in named.subtracting(planned) {
            #expect(help.contains(option),
                    "the design document spells `\(option)` in the suggest usage line, but the parser does not accept it — either ship it or list it as planned beneath the block")
        }
        for option in planned where help.contains(option) {
            Issue.record("`\(option)` is listed as planned but the parser now accepts it — move it into the usage line")
        }
    }

    /// The fenced block under "porcelain" in §6.1 — the list a reader takes as "what I can run".
    static func porcelainBlock(_ design: String) -> String? {
        guard let anchor = design.range(of: "skillet init        # adopt skillet in a repo") else { return nil }
        let rest = design[anchor.lowerBound...]
        return String(rest[..<(rest.range(of: "\n```")?.lowerBound ?? rest.endIndex)])
    }

    /// The fenced usage line under the `#### \`skillet suggest\`` heading.
    static func suggestSynopsis(_ design: String) -> String? {
        guard let heading = design.range(of: "#### `skillet suggest`") else { return nil }
        let rest = design[heading.upperBound...]
        guard let open = rest.range(of: "```") else { return nil }
        let body = rest[open.upperBound...]
        return String(body[..<(body.range(of: "```")?.lowerBound ?? body.endIndex)])
    }

    /// Options the design document itself declares not-yet-available, read from the line beneath the
    /// usage block so the exemption lives next to the claim it exempts.
    static func plannedOptions(_ design: String) -> [String] {
        guard let heading = design.range(of: "#### `skillet suggest`") else { return [] }
        let rest = design[heading.upperBound...]
        let window = String(rest.prefix(2_000))
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
