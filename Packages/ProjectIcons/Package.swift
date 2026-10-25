// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProjectIcons",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ProjectIcons", targets: ["ProjectIcons"])
    ],
    targets: [
        .target(
            name: "ProjectIcons",
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "ProjectIconsTests", dependencies: ["ProjectIcons"]),
    ]
)
