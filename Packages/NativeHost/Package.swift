// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeHost",
    // The protocol and client build for iOS too, for the companion app; the host itself is macOS only.
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
    ],
    targets: [
        .target(name: "NativeHostProtocol", dependencies: ["ACP"]),
        .target(name: "UserShell"),
        /// The host's core: portable (Foundation only), so other machines can run it.
        .target(name: "NativeHost", dependencies: ["NativeHostProtocol", "ACP"]),
        /// The Mac's side of the host: code-signature checks, boot time, the login-shell environment.
        .target(
            name: "NativeHostMac",
            dependencies: [
                "NativeHost", "NativeHostProtocol", "UserShell", .product(name: "Exec", package: "Exec"),
                .product(name: "HostUpdater", package: "HostUpdater"),
            ]),
        .target(
            name: "NativeHostClient",
            dependencies: ["NativeHostProtocol", "ACP", .product(name: "Exec", package: "Exec")]),
        .executableTarget(name: "native-host", dependencies: ["NativeHost", "NativeHostMac", "NativeHostProtocol"]),
        /// A scriptable ACP agent for the crash-recovery tests.
        .executableTarget(name: "FakeACPAgent", dependencies: ["NativeHostProtocol", "ACP"]),
        .testTarget(
            name: "NativeHostTests",
            dependencies: [
                "NativeHost", "NativeHostMac", "NativeHostClient", "NativeHostProtocol", "ACP",
                .product(name: "Exec", package: "Exec"), "native-host", "FakeACPAgent",
            ]
        ),
    ]
)
