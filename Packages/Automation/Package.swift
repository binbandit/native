// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Automation",
    // iOS too: goals, workflows and automations run on the host, and their state crosses the host
    // protocol to every client.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativeAutomation", targets: ["NativeAutomation"])
    ],
    targets: [
        .target(name: "NativeAutomation"),
        .testTarget(name: "NativeAutomationTests", dependencies: ["NativeAutomation"]),
    ]
)
