// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Git",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Git", targets: ["Git"])
    ],
    dependencies: [
        .package(path: "../Exec")
    ],
    targets: [
        .target(name: "Git", dependencies: [.product(name: "Exec", package: "Exec")]),
        .testTarget(name: "GitTests", dependencies: ["Git"]),
    ]
)
