import Foundation
import Subprocess
import Testing
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// Runs the built `skillet` binary in integration tests (the command surface lives in the
/// executable, so this is how it's exercised). Locates the binary relative to the test bundle —
/// robust to working directory and build configuration — with a `SKILLET_TEST_BINARY` override.
struct SkilletHarness {
    let executable: FilePath

    init() throws {
        let path: String
        if let override = ProcessInfo.processInfo.environment["SKILLET_TEST_BINARY"], !override.isEmpty {
            path = override
        } else {
            path = Self.productsDirectory.appendingPathComponent("skillet").path
        }
        try #require(
            FileManager.default.fileExists(atPath: path),
            "skillet binary not found at \(path) — run `swift build` first"
        )
        self.executable = FilePath(path)
    }

    struct Output {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    @discardableResult
    func run(_ arguments: [String], workingDirectory: URL? = nil, environment: [String: String]? = nil) async throws -> Output {
        // An overlay layers on the parent env (PATH etc. survive) — the doctor tests use this to pin
        // SKILLET_CLAUDE_CODE_BIN at a shim binary.
        //
        // Every invocation enables the hidden test-only options, which the binary otherwise refuses: they
        // are what keeps the suite offline and free. Set here, once, rather than at ~90 call sites. A test
        // proving the refusal passes an empty value for this variable — empty counts as unset, which is
        // the only way to "remove" a variable through an overlay.
        var merged = ["SKILLET_TEST_SEAMS": "1"]
        merged.merge(environment ?? [:]) { _, fromTest in fromTest }
        let env: Environment = .inherit.updating(Dictionary(uniqueKeysWithValues: merged.map {
            (Environment.Key(stringLiteral: $0.key), Optional($0.value))
        }))
        let result = try await Subprocess.run(
            .path(executable),
            arguments: .init(arguments),
            environment: env,
            workingDirectory: workingDirectory.map { FilePath($0.path) },
            output: .string(limit: 1 << 20),
            error: .string(limit: 1 << 20)
        )
        let code: Int32
        if case .exited(let value) = result.terminationStatus {
            code = value
        } else {
            code = -1
        }
        return Output(
            stdout: result.standardOutput ?? "",
            stderr: result.standardError ?? "",
            exitCode: code
        )
    }

    /// Directory containing the built products (the `skillet` binary).
    static var productsDirectory: URL {
        #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        #else
        // The test runner is itself a binary sitting in whatever folder the build actually wrote to,
        // next to the one under test. Ask it where it is rather than assuming the default folder name:
        // point a build at a different folder and the assumption reaches into an unrelated one, where
        // a leftover binary answers every check with an older version's behaviour and still reads green.
        if let runner = Bundle.main.executableURL {
            return runner.deletingLastPathComponent()
        }
        #endif
        // Last resort: <package root>/.build/debug (swift test runs from the package root).
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug", isDirectory: true)
    }
}
