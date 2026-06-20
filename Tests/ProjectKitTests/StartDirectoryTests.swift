import Testing
import Foundation
import EDDCore
import ProjectKit

@Suite("-C resolution")
struct StartDirectoryTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("No -C uses the current directory")
    func noDashCUsesCwd() throws {
        let start = try ProjectLocator(probe: InMemoryProbe()).resolveStart(dashC: nil, cwd: url("/here"))
        #expect(start.path == "/here")
    }

    @Test("Relative -C resolves against the current directory")
    func relativeDashC() throws {
        let probe = InMemoryProbe(readableDirectories: ["/here/sub"])
        let start = try ProjectLocator(probe: probe).resolveStart(dashC: "sub", cwd: url("/here"))
        #expect(start.path == "/here/sub")
    }

    @Test("A missing/unreadable -C directory is an environment error")
    func missingDashCThrows() {
        let locator = ProjectLocator(probe: InMemoryProbe()) // nothing readable
        #expect(throws: EDDError.directoryNotFound(path: "/no/such")) {
            try locator.resolveStart(dashC: "/no/such", cwd: url("/here"))
        }
    }
}
