// swift-tools-version: 6.2
import PackageDescription

// The engine behind a crew of agents working through an approved route. Neutral working name until
// the feature's name is settled (docs/expeditions.md).
let package = Package(
    name: "Teamwork",
    // iOS too: the engine runs on a host, and its state crosses the host protocol to every client.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativeTeamwork", targets: ["NativeTeamwork"]),
    ],
    dependencies: [
        .package(path: "../Automation"),
    ],
    targets: [
        .target(name: "NativeTeamwork", dependencies: [.product(name: "NativeAutomation", package: "Automation")]),
        .testTarget(name: "NativeTeamworkTests", dependencies: ["NativeTeamwork"]),
    ]
)
