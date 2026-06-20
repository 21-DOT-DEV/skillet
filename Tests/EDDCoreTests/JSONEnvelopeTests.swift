import Testing
import EDDCore

@Suite("JSON envelope")
struct JSONEnvelopeTests {
    @Test("Root payload encodes deterministically with a schema field (golden)")
    func rootGolden() throws {
        let info = RootInfo(
            skilletVersion: "1.2.3",
            project: ProjectContext(root: "/repo", discoveredVia: .gitBoundary, cwd: "/repo/sub", configPath: nil),
            loop: [LoopVerb(name: "run", summary: "measure")]
        )
        let json = try SkilletJSON.encode(info)
        #expect(json == #"{"loop":[{"name":"run","summary":"measure"}],"project":{"cwd":"/repo/sub","discovered_via":"git_boundary","root":"/repo"},"schema":"skillet.root/1","skillet_version":"1.2.3"}"#)
    }

    @Test("nil optionals are omitted, not encoded as null")
    func omitsNilOptionals() throws {
        let info = RootInfo(
            skilletVersion: "0",
            project: ProjectContext(root: nil, discoveredVia: .none, cwd: "/x", configPath: nil),
            loop: []
        )
        let json = try SkilletJSON.encode(info)
        #expect(!json.contains(#""root":"#)) // the `root` key is omitted ("root" still appears in the schema value)
        #expect(!json.contains("config_path"))
        #expect(!json.contains("null"))
        #expect(json.contains(#""discovered_via":"none""#))
    }

    @Test("Encoding is stable across runs")
    func deterministic() throws {
        let info = RootInfo(
            skilletVersion: "9",
            project: ProjectContext(root: "/a", discoveredVia: .skilletYAML, cwd: "/a", configPath: "/a/skillet.yaml"),
            loop: LoopVerb.canonical
        )
        #expect(try SkilletJSON.encode(info) == (try SkilletJSON.encode(info)))
    }

    @Test("Error payload carries schema, numeric code, and kind")
    func errorPayload() throws {
        let json = try SkilletJSON.encode(ErrorPayload(.directoryNotFound(path: "/no/such")))
        #expect(json.contains(#""schema":"skillet.error/1""#))
        #expect(json.contains(#""code":3"#))
        #expect(json.contains(#""kind":"directory_not_found""#))
    }
}
