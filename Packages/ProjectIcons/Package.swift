// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProjectIcons",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ProjectIcons", targets: ["ProjectIcons"])
    ],
    targets: [
        .target(name: "ProjectIcons"),
        .testTarget(name: "ProjectIconsTests", dependencies: ["ProjectIcons"]),
    ]
)
