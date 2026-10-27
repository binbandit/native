// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Orchestration",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        /// Native's orchestration engine: the tools agents hand each other tasks with, over whatever
        /// runs the sessions (the host, or the app when agents run inside it).
        .library(name: "NativeOrchestration", targets: ["NativeOrchestration"])
    ],
    dependencies: [
        .package(path: "../ACP"),
        .package(path: "../MCPServer"),
    ],
    targets: [
        .target(
            name: "NativeOrchestration",
            dependencies: [.product(name: "ACP", package: "ACP"), .product(name: "MCP", package: "MCPServer")],
            resources: [.copy("Resources/native-app")],
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(
            name: "NativeOrchestrationTests",
            dependencies: [
                "NativeOrchestration", .product(name: "ACP", package: "ACP"),
                .product(name: "MCP", package: "MCPServer"),
            ]),
    ]
)
