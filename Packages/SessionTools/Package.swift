// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SessionTools",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SessionTools", targets: ["SessionTools"])
    ],
    targets: [
        .target(name: "SessionTools"),
        .testTarget(name: "SessionToolsTests", dependencies: ["SessionTools"]),
    ]
)
