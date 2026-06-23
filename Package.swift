// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// MARK: - skillet — the SKILL.md Evaluation Toolkit
//
// Phase-1 subset of the design §11 architecture. The `skillet` executable owns ALL argument-parser
// logic and wiring; business logic lives in kit libraries that are unit-tested in isolation.
// Strictly downward dependency DAG:
//
//   skillet (executable, .Cxx) ──▶ ConfigYAML · HarnessKit · ProjectKit · RenderKit · TraceKit · EDDCore
//        ConfigYAML (.Cxx) ──▶ swift-yaml (YAML) + EDDCore        — isolates C++ interop
//        HarnessKit ──▶ TraceKit · EDDCore · swift-subprocess
//        ProjectKit / RenderKit ──▶ EDDCore
//        EDDCore (pure: Foundation only — no subprocess, no network, no swift-yaml)
//
// swift-yaml's C++ interop is viral to direct importers, so it is confined to ConfigYAML; the
// executable (a leaf consumer) is .Cxx too, but the kits + pure core stay interop-free (AGENTS.md).

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
        // The sole sanctioned process launcher — used by HarnessKit's ProcessLauncher (F6) and
        // the integration-test binary harness.
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.2.1"),
        // Provides `FilePath` for HarnessKit's launcher and the integration-test harness
        // (via swift-subprocess).
        .package(url: "https://github.com/apple/swift-system", exact: "1.5.0"),
        // YAML config parsing. No tagged release → pinned by revision (see Package.resolved). Its
        // `YAML` product needs C++ interop, so it is confined to the `ConfigYAML` target below; the
        // pure core (EDDCore) and the executable stay interop-free.
        .package(url: "https://github.com/21-DOT-DEV/swift-yaml", revision: "e8d1769427b6781cc9088f2dfe029b44073fee52")
    ],
    targets: [
        // MARK: Layer 0 — pure core (no I/O, no processes, no network)
        .target(name: "EDDCore"),

        // MARK: Layer 1 — normalized trace model
        .target(name: "TraceKit", dependencies: ["EDDCore"]),

        // MARK: Layer 2 — mechanism (effectful kits over the pure core)
        .target(name: "ProjectKit", dependencies: ["EDDCore"]),
        .target(name: "RenderKit", dependencies: ["EDDCore"]),
        .target(
            name: "HarnessKit",
            dependencies: [
                "TraceKit",
                "EDDCore",
                // Sole sanctioned launcher — for the real ProcessLauncher (probe; F7's run).
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system")
            ]
        ),

        // Isolated YAML config seam: swift-yaml + C++ interop live ONLY here. It exposes a pure-Swift
        // API (decodes into EDDCore's pure SkilletConfig), so consumers stay interop-free.
        .target(
            name: "ConfigYAML",
            dependencies: [
                "EDDCore",
                .product(name: "YAML", package: "swift-yaml")
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),

        // MARK: Layer 4 — the executable: ALL ArgumentParser commands + wiring
        .executableTarget(
            name: "skillet",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "EDDCore",
                "ProjectKit",
                "RenderKit",
                "TraceKit",
                "HarnessKit",
                // Config loading. Importing ConfigYAML pulls in C++ interop (viral to direct
                // importers), so this leaf target is .Cxx too; the kits + pure core stay interop-free.
                "ConfigYAML"
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),

        // MARK: Unit tests — one target per kit (each proven importable in isolation)
        .testTarget(name: "EDDCoreTests", dependencies: ["EDDCore"]),
        .testTarget(name: "TraceKitTests", dependencies: ["TraceKit"]),
        .testTarget(name: "ProjectKitTests", dependencies: ["ProjectKit"]),
        .testTarget(name: "RenderKitTests", dependencies: ["RenderKit"]),
        .testTarget(name: "HarnessKitTests", dependencies: ["HarnessKit"]),
        // Consumer of ConfigYAML — must also enable C++ interop (it's viral to direct importers).
        .testTarget(name: "ConfigYAMLTests", dependencies: ["ConfigYAML"], swiftSettings: [.interoperabilityMode(.Cxx)]),

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
