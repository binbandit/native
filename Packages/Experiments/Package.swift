// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Experiments",
    // UI-free, so the host and the companion can resolve the same contracts as the app.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Experiments", targets: ["Experiments"]),
    ],
    targets: [
        .target(name: "Experiments"),
        .testTarget(name: "ExperimentsTests", dependencies: ["Experiments"]),
    ]
)
