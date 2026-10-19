// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIInstructions",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "AIInstructions", targets: ["AIInstructions"])
    ],
    targets: [
        .target(name: "AIInstructions"),
        .testTarget(name: "AIInstructionsTests", dependencies: ["AIInstructions"]),
    ]
)
