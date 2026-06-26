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
        .init(args: ["lint", "--help"], exit: 0)
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
        #expect(names.contains("lint"))
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
}
