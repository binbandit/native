// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeHost",
    // The protocol and client build for iOS too, for the companion app; the host builds for macOS and
    // Linux (docs/durability.md, "Any machine can be a host").
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        /// The background host: agent processes, sessions, the store and the IPC server.
        .library(name: "NativeHost", targets: ["NativeHost", "NativeHostMac", "NativeHostProtocol", "UserShell"]),
        /// What the app (and later the companion) links to talk to the host: the client, the wire
        /// types it shares with the host, and the login-shell environment.
        .library(name: "NativeHostClient", targets: ["NativeHostClient", "NativeHostProtocol", "UserShell"]),
        /// A host binary for tests and development; the app embeds its own helper.
        .executable(name: "native-host", targets: ["native-host"]),
    ],
    dependencies: [
        .package(path: "../ACP"),
        .package(path: "../Exec"),
        .package(path: "../HostUpdater"),
        .package(path: "../Orchestration"),
        .package(path: "../MCPServer"),
        .package(path: "../SessionTitling"),
        // The Mac host's policy source: the managed preferences Native's app reads, read by the host.
        .package(path: "../NativePolicy"),
        .package(path: "../NativeNetwork"),
        // Tests only: Git running against a host through `RemoteCommandRunner`.
        .package(path: "../Git"),
        // Tests only: MCP browser sign-in through the paired command runner.
        .package(path: "../MCPClient"),
    ],
    targets: [
        .target(name: "NativeHostProtocol", dependencies: ["ACP"]),
        .target(name: "UserShell"),
        /// The system SQLite on Linux, which Apple's SDKs have as the `SQLite3` module.
        .systemLibrary(name: "CSQLite"),
        /// Linux path-only directory descriptors, whose flags Swift's Glibc module doesn't expose.
        .target(name: "CHostPOSIX"),
        /// The host's core: portable (Foundation only), so other machines can run it.
        .target(
            name: "NativeHost",
            dependencies: [
                "NativeHostProtocol", "ACP", .product(name: "Exec", package: "Exec"),
                .product(name: "NativePolicy", package: "NativePolicy"),
                .product(name: "NativeNetwork", package: "NativeNetwork"),
                .product(name: "NativeOrchestration", package: "Orchestration"),
                .product(name: "MCP", package: "MCPServer"),
                .product(name: "SessionTitling", package: "SessionTitling"),
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
                .target(name: "CHostPOSIX", condition: .when(platforms: [.linux])),
            ]),
        /// The Mac's side of the host: code-signature checks, boot time, the login-shell environment.
        .target(
            name: "NativeHostMac",
            dependencies: [
                "NativeHost", "NativeHostProtocol", "UserShell", .product(name: "Exec", package: "Exec"),
                // Conditional even though this target is macOS-only: SwiftPM still builds a dependency's
                // products elsewhere, and HostUpdater's Ed25519 is CryptoKit's (docs/durability.md).
                .product(name: "HostUpdater", package: "HostUpdater", condition: .when(platforms: [.macOS])),
                .product(name: "SessionTitling", package: "SessionTitling"),
                .product(name: "NativeOrchestration", package: "Orchestration"),
                .product(name: "NativePolicy", package: "NativePolicy", condition: .when(platforms: [.macOS])),
            ]),
        .target(
            name: "NativeHostClient",
            dependencies: ["NativeHostProtocol", "ACP", .product(name: "Exec", package: "Exec")]),
        /// Elsewhere than macOS it runs without the Mac's pieces (main.swift says which).
        .executableTarget(
            name: "native-host",
            dependencies: [
                "NativeHost", .target(name: "NativeHostMac", condition: .when(platforms: [.macOS])),
                "NativeHostProtocol", "UserShell",
            ]),
        /// A scriptable ACP agent for the crash-recovery tests.
        .executableTarget(name: "FakeACPAgent", dependencies: ["NativeHostProtocol", "ACP"]),
        .testTarget(
            name: "NativeHostTests",
            dependencies: [
                "NativeHost", .target(name: "NativeHostMac", condition: .when(platforms: [.macOS])),
                "NativeHostClient", "NativeHostProtocol", "ACP", .product(name: "Exec", package: "Exec"),
                .product(name: "Git", package: "Git"), "native-host",
                "FakeACPAgent", .product(name: "SessionTitling", package: "SessionTitling"),
                .product(name: "MCPClient", package: "MCPClient", condition: .when(platforms: [.macOS])),
                .product(name: "NativeOrchestration", package: "Orchestration"),
                .product(name: "NativePolicy", package: "NativePolicy", condition: .when(platforms: [.macOS])),
            ]
        ),
    ]
)
