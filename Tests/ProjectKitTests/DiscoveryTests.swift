import Testing
import Foundation
import EDDCore
import ProjectKit

@Suite("Project discovery")
struct DiscoveryTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("Finds skillet.yaml walking up from a deep subdirectory")
    func findsSkilletYAML() {
        let probe = InMemoryProbe(entries: ["/repo": ["skillet.yaml"]])
        let context = ProjectLocator(probe: probe).discover(from: url("/repo/a/b/c"))
        #expect(context.root == "/repo")
        #expect(context.discoveredVia == .skilletYAML)
        #expect(context.cwd == "/repo/a/b/c")
    }

    @Test("Stops at a .git boundary when no skillet.yaml exists")
    func stopsAtGitBoundary() {
        let probe = InMemoryProbe(entries: ["/repo": [".git"]])
        let context = ProjectLocator(probe: probe).discover(from: url("/repo/pkg"))
        #expect(context.root == "/repo")
        #expect(context.discoveredVia == .gitBoundary)
    }

    @Test("skillet.yaml wins over .git in the same directory")
    func skilletYAMLWinsOverGit() {
        let probe = InMemoryProbe(entries: ["/repo": ["skillet.yaml", ".git"]])
        let context = ProjectLocator(probe: probe).discover(from: url("/repo"))
        #expect(context.discoveredVia == .skilletYAML)
    }

    @Test("No project found is benign: root is nil, discoveredVia is none")
    func noProjectIsBenign() {
        let context = ProjectLocator(probe: InMemoryProbe()).discover(from: url("/tmp/x/y"))
        #expect(context.root == nil)
        #expect(context.discoveredVia == .none)
        #expect(context.cwd == "/tmp/x/y")
    }
}
