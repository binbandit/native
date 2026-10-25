// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SessionTools",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SessionTools", targets: ["SessionTools"])
    ],
    targets: [
        .target(
            name: "SessionTools",
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "SessionToolsTests", dependencies: ["SessionTools"]),
    ]
)
