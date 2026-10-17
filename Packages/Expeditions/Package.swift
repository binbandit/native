// swift-tools-version: 6.2
import PackageDescription

// Expeditions: a crew of agents working through a route the user approved (docs/expeditions.md).
let package = Package(
    name: "Expeditions",
    // iOS too: the engine runs on a host, and its state crosses the host protocol to every client.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativeExpeditions", targets: ["NativeExpeditions"]),
    ],
    dependencies: [
        .package(path: "../Automation"),
    ],
    targets: [
        .target(name: "NativeExpeditions", dependencies: [.product(name: "NativeAutomation", package: "Automation")]),
        .testTarget(name: "NativeExpeditionsTests", dependencies: ["NativeExpeditions"]),
    ]
)
