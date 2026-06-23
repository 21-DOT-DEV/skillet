import Foundation

/// A small seam over executable lookup so the resolution chain is unit-testable without a real PATH.
public protocol ExecutableProbe: Sendable {
    func isExecutable(_ path: String) -> Bool
    func lookInPATH(_ name: String) -> String?
}

/// The real, `FileManager`/`PATH`-backed probe.
public struct SystemExecutableProbe: ExecutableProbe {
    let environment: [String: String]
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func lookInPATH(_ name: String) -> String? {
        guard let path = environment["PATH"] else { return nil }
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

/// A resolved harness binary plus which link of the chain produced it (printable, §9.1).
public struct ResolvedBinary: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case flag, env, config, path, vendored
    }
    public var path: String
    public var source: Source
    public init(path: String, source: Source) {
        self.path = path
        self.source = source
    }

    /// Explicitly pinned (flag/env/config) vs. auto-discovered (PATH/vendored) — drives the ban policy.
    public var isPinned: Bool { source == .flag || source == .env || source == .config }
}

/// Resolves a harness binary along the fixed chain (§9.1):
/// `--harness-path` flag > `SKILLET_<ID>_BIN` env > `[harness.<id>].path` config > PATH > vendored.
public struct BinaryResolver: Sendable {
    let probe: ExecutableProbe
    let environment: [String: String]

    public init(
        probe: ExecutableProbe = SystemExecutableProbe(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.probe = probe
        self.environment = environment
    }

    /// Returns the resolved binary + winning link, or `nil` if none. Existence/version/denylist
    /// validation happens at `probe()`; explicit pins (flag/env/config) are authoritative.
    public func resolve(flag: String?, envVar: String, configPath: String?, pathName: String) -> ResolvedBinary? {
        if let flag, !flag.isEmpty { return ResolvedBinary(path: flag, source: .flag) }
        if let env = environment[envVar], !env.isEmpty { return ResolvedBinary(path: env, source: .env) }
        if let configPath, !configPath.isEmpty { return ResolvedBinary(path: configPath, source: .config) }
        if let found = probe.lookInPATH(pathName) { return ResolvedBinary(path: found, source: .path) }
        // vendored search: deferred (opt-in via `harness which --search`).
        return nil
    }
}
