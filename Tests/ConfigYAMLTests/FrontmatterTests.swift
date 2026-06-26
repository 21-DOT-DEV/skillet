import Testing
import EDDCore
import ConfigYAML

@Suite("SKILL.md frontmatter parser")
struct FrontmatterTests {
    @Test("Splits frontmatter and body; decodes name + description")
    func splitsAndDecodes() throws {
        let markdown = """
        ---
        name: docc-articles
        description: Write great DocC.
        ---
        # Body
        Hello.
        """
        let (frontmatter, body) = try FrontmatterParser.parse(markdown)
        #expect(frontmatter.name == "docc-articles")
        #expect(frontmatter.description == "Write great DocC.")
        #expect(body == "# Body\nHello.")
    }

    @Test("Folds a folded (>) block scalar into one line")
    func foldsScalar() throws {
        let markdown = """
        ---
        name: x
        description: >
          one two
          three four
        ---
        body
        """
        let (frontmatter, _) = try FrontmatterParser.parse(markdown)
        // Folded: interior newlines become spaces. (Trailing-newline chomping varies by parser, so
        // compare the trimmed value — the point is that folding happened before L001 counts it.)
        #expect(frontmatter.description?.trimmingCharacters(in: .whitespacesAndNewlines) == "one two three four")
    }

    @Test("An empty frontmatter block is valid (all fields nil)")
    func emptyBlock() throws {
        let (frontmatter, body) = try FrontmatterParser.parse("---\n---\nbody\n")
        #expect(frontmatter.name == nil)
        #expect(frontmatter.description == nil)
        #expect(body == "body\n")
    }

    @Test("CRLF line endings are normalized — no stray \\r in fields or body")
    func crlf() throws {
        let (frontmatter, body) = try FrontmatterParser.parse("---\r\nname: demo\r\ndescription: hi there\r\n---\r\n# Body\r\nline two\r\n")
        #expect(frontmatter.name == "demo")
        #expect(frontmatter.description == "hi there")
        #expect(body == "# Body\nline two\n")
        #expect(!body.contains("\r"))
    }

    @Test("No leading --- is .missing")
    func missing() {
        #expect(throws: FrontmatterError.missing) {
            _ = try FrontmatterParser.parse("# Just a heading\nno frontmatter\n")
        }
    }

    @Test("An unterminated block is .unterminated")
    func unterminated() {
        #expect(throws: FrontmatterError.unterminated) {
            _ = try FrontmatterParser.parse("---\nname: x\nno closing fence\n")
        }
    }

    @Test("Undecodable YAML is a typed .undecodable, not an uncaught throw")
    func undecodable() {
        // An unclosed quoted scalar is a hard YAML parse error.
        #expect(throws: FrontmatterError.self) {
            _ = try FrontmatterParser.parse("---\ndescription: \"unterminated\n---\nbody\n")
        }
    }
}
