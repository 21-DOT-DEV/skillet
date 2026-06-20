import Testing
import EDDCore
import RenderKit

@Suite("Renderer")
struct RendererTests {
    private func sampleRoot() -> RootInfo {
        RootInfo(
            skilletVersion: "0",
            project: ProjectContext(root: "/repo", discoveredVia: .skilletYAML, cwd: "/repo", configPath: nil),
            loop: LoopVerb.canonical
        )
    }

    @Test("JSON root goes to stdout, carries the schema, leaves stderr empty")
    func jsonRoot() throws {
        let rendering = try Renderer(mode: .json, color: ColorPolicy(enabled: false)).renderRoot(sampleRoot())
        #expect(rendering.stdout.contains(#""schema":"skillet.root/1""#))
        #expect(rendering.stderr.isEmpty)
    }

    @Test("Human root explains the loop on stdout")
    func humanRoot() throws {
        let rendering = try Renderer(mode: .human, color: ColorPolicy(enabled: false)).renderRoot(sampleRoot())
        #expect(rendering.stdout.contains("skillet"))
        #expect(rendering.stdout.contains("run"))
        #expect(rendering.stdout.contains("Project: /repo"))
        #expect(rendering.stderr.isEmpty)
    }

    @Test("JSON error goes to stderr with the error schema; stdout stays empty")
    func jsonError() {
        let rendering = Renderer(mode: .json, color: ColorPolicy(enabled: false)).renderError(.directoryNotFound(path: "/x"))
        #expect(rendering.stdout.isEmpty)
        #expect(rendering.stderr.contains(#""schema":"skillet.error/1""#))
        #expect(rendering.stderr.contains(#""code":3"#))
    }

    @Test("Human error is what/why/fix on stderr; no ANSI when color is off")
    func humanErrorNoColor() {
        let rendering = Renderer(mode: .human, color: ColorPolicy(enabled: false)).renderError(.directoryNotFound(path: "/x"))
        #expect(rendering.stderr.contains("error:"))
        #expect(rendering.stderr.contains("fix:"))
        #expect(!rendering.stderr.contains("\u{1B}["))
    }

    @Test("Color on emits ANSI escapes")
    func colorOnEmitsANSI() throws {
        let root = try Renderer(mode: .human, color: ColorPolicy(enabled: true)).renderRoot(sampleRoot())
        #expect(root.stdout.contains("\u{1B}[1m"))
        let error = Renderer(mode: .human, color: ColorPolicy(enabled: true)).renderError(.directoryNotFound(path: "/x"))
        #expect(error.stderr.contains("\u{1B}[31m"))
    }
}
