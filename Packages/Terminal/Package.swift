// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Terminal",
    // UI-free, so a host can own terminal sessions and every client can render them the same way.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Terminal", targets: ["Terminal"])
    ],
    targets: [
        .target(
            name: "Terminal",
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "TerminalTests", dependencies: ["Terminal"]),
    ]
)
