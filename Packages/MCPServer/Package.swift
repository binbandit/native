// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MCPServer",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MCP", targets: ["MCP"])
    ],
    targets: [
        .target(
            name: "MCP",
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "MCPTests", dependencies: ["MCP"]),
    ]
)
