// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MCPClient",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MCPClient", targets: ["MCPClient"]),
    ],
    dependencies: [
        // For the protocol's `JSON` type, and in tests, a real server to probe.
        .package(path: "../MCPServer"),
    ],
    targets: [
        .target(name: "MCPClient", dependencies: [.product(name: "MCP", package: "MCPServer")]),
        .testTarget(
            name: "MCPClientTests",
            dependencies: ["MCPClient", .product(name: "MCP", package: "MCPServer")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
