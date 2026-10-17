// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Git",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Git", targets: ["Git"])
    ],
    targets: [
        .target(name: "Git"),
        .testTarget(name: "GitTests", dependencies: ["Git"]),
    ]
)
