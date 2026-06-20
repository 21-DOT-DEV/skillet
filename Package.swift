// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// MARK: - skillet — the SKILL.md Evaluation Toolkit
//
// Phase-1 / F1 subset of the design §11 architecture. The `skillet` executable owns ALL
// argument-parser logic and wiring; business logic lives in kit libraries that are unit-tested
// in isolation. Strictly downward dependency DAG:
//
//   skillet (executable) ──▶ ProjectKit · RenderKit · EDDCore
//        ProjectKit / RenderKit ──▶ EDDCore
//        EDDCore (pure: Foundation only — no subprocess, no network, no swift-yaml yet)
//
// Later features add their kits (HarnessKit/JudgeKit/RunKit/LintKit, …). swift-yaml is wired
// only when EDDCore's config codec lands (see AGENTS.md › Dependency notes).

let package = Package(
    name: "skillet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "skillet", targets: ["skillet"])
    ],
    dependencies: [
        // CLI argument parsing — owned entirely by the `skillet` executable target.
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.6.2"),
        // The sole sanctioned process launcher — used here only by the integration-test binary
        // harness in F1 (effectful kits adopt it in later features).
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.2.1"),
        // Provides `FilePath` for the integration-test harness. Transitive via swift-subprocess;
        // declared for test-only use, so it adds no shipped runtime dependency.
        .package(url: "https://github.com/apple/swift-system", exact: "1.5.0")
    ],
    targets: [
        // MARK: Layer 0 — pure core (no I/O, no processes, no network)
        .target(name: "EDDCore"),

        // MARK: Layer 2 — mechanism (effectful kits over the pure core)
        .target(name: "ProjectKit", dependencies: ["EDDCore"]),
        .target(name: "RenderKit", dependencies: ["EDDCore"]),

        // MARK: Layer 4 — the executable: ALL ArgumentParser commands + wiring
        .executableTarget(
            name: "skillet",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "EDDCore",
                "ProjectKit",
                "RenderKit"
            ]
        ),

        // MARK: Unit tests — one target per kit (each proven importable in isolation)
        .testTarget(name: "EDDCoreTests", dependencies: ["EDDCore"]),
        .testTarget(name: "ProjectKitTests", dependencies: ["ProjectKit"]),
        .testTarget(name: "RenderKitTests", dependencies: ["RenderKit"]),

        // MARK: Integration tests — drive the built BINARY (commands live in the executable, so
        // the binary harness is the only way to exercise the command tree). Does NOT import the kits.
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
