import Testing
import HarnessKit

// FakeExecutableProbe + FakeLauncher live in Fakes.swift (shared across the suite).

@Suite("Binary resolution & denylist")
struct ResolutionTests {
    @Test("Resolution picks the highest-priority link")
    func resolutionOrder() {
        let probe = FakeExecutableProbe(pathLookup: ["claude": "/usr/bin/claude"])
        let withEnv = BinaryResolver(probe: probe, environment: ["SKILLET_CLAUDE_CODE_BIN": "/env/claude"])
        #expect(withEnv.resolve(flag: "/flag/claude", envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: "/cfg/claude", pathName: "claude")?.source == .flag)
        #expect(withEnv.resolve(flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: "/cfg/claude", pathName: "claude")?.source == .env)

        let noEnv = BinaryResolver(probe: probe, environment: [:])
        #expect(noEnv.resolve(flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: "/cfg/claude", pathName: "claude")?.source == .config)
        #expect(noEnv.resolve(flag: nil, envVar: "SKILLET_CLAUDE_CODE_BIN", configPath: nil, pathName: "claude")?.source == .path)

        let empty = BinaryResolver(probe: FakeExecutableProbe(), environment: [:])
        #expect(empty.resolve(flag: nil, envVar: "X", configPath: nil, pathName: "claude") == nil)
    }

    @Test("isPinned reflects explicit links")
    func pinned() {
        #expect(ResolvedBinary(path: "/x", source: .flag).isPinned)
        #expect(ResolvedBinary(path: "/x", source: .config).isPinned)
        #expect(!ResolvedBinary(path: "/x", source: .path).isPinned)
    }

    @Test("Denylist: pinned-banned refused, auto-banned warned, bypass/clean allowed")
    func denylist() {
        let list = Denylist.claudeCodeSeed
        #expect(list.check(version: "2.1.143", pinned: true, bypassed: false) == .refused(version: "2.1.143"))
        #expect(list.check(version: "2.1.143", pinned: false, bypassed: false) == .warnedFallback(version: "2.1.143"))
        #expect(list.check(version: "2.1.143", pinned: true, bypassed: true) == .allowed)
        #expect(list.check(version: "2.1.144", pinned: true, bypassed: false) == .allowed)
    }
}
