// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OrchestrationEvals",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NativeToolEvals", targets: ["NativeToolEvals"]),
        .executable(name: "native-tool-evals", targets: ["ToolEvalCLI"]),
    ],
    dependencies: [
        .package(path: "../Orchestration"),
        .package(path: "../MCPServer"),
        .package(path: "../NativeNetwork"),
        .package(path: "../NativePolicy"),
    ],
    targets: [
        .target(
            name: "NativeToolEvals",
            dependencies: [
                .product(name: "NativeOrchestration", package: "Orchestration"),
                .product(name: "MCP", package: "MCPServer"),
                .product(name: "NativeNetwork", package: "NativeNetwork"),
                .product(name: "NativePolicy", package: "NativePolicy"),
            ]),
        .executableTarget(name: "ToolEvalCLI", dependencies: ["NativeToolEvals"]),
        .testTarget(name: "NativeToolEvalsTests", dependencies: ["NativeToolEvals"]),
    ]
)
