// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Git",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Git", targets: ["Git"])
    ],
    dependencies: [
        .package(path: "../Exec"),
        .package(path: "../AIInstructions"),
    ],
    targets: [
        .target(
            name: "Git",
            dependencies: [
                .product(name: "Exec", package: "Exec"),
                .product(name: "AIInstructions", package: "AIInstructions"),
            ],
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(
            name: "GitTests", dependencies: ["Git", .product(name: "AIInstructions", package: "AIInstructions")]),
    ]
)
