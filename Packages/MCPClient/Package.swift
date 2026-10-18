// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MCPClient",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MCPClient", targets: ["MCPClient"])
    ],
    dependencies: [
        // For the protocol's `JSON` type, and in tests, a real server to probe.
        .package(path: "../MCPServer"),
        // Agents' CLIs run through a `CommandRunner`, so they can run on whichever host owns the project.
        .package(path: "../Exec"),
        // What an organization allows, so the servers it doesn't stay out of sessions.
        .package(path: "../NativePolicy"),
    ],
    targets: [
        .target(
            name: "MCPClient",
            dependencies: [
                .product(name: "MCP", package: "MCPServer"),
                .product(name: "Exec", package: "Exec"),
                .product(name: "NativePolicy", package: "NativePolicy"),
            ]),
        .testTarget(
            name: "MCPClientTests",
            dependencies: [
                "MCPClient", .product(name: "MCP", package: "MCPServer"), .product(name: "Exec", package: "Exec"),
                .product(name: "NativePolicy", package: "NativePolicy"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
