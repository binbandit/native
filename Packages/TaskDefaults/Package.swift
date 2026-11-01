// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TaskDefaults",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "TaskDefaults", targets: ["TaskDefaults"])],
    targets: [
        .target(name: "TaskDefaults"),
        .testTarget(name: "TaskDefaultsTests", dependencies: ["TaskDefaults"]),
    ]
)
