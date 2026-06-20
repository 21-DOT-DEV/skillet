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
    func run(_ arguments: [String], workingDirectory: URL? = nil) async throws -> Output {
        let result = try await Subprocess.run(
            .path(executable),
            arguments: .init(arguments),
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
        #endif
        // Fallback: <package root>/.build/debug (swift test runs from the package root).
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug", isDirectory: true)
    }
}
