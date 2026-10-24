// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitHub",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "GitHub", targets: ["GitHub"])
    ],
    dependencies: [
        .package(path: "../Exec"),
        .package(path: "../AIInstructions"),
    ],
    targets: [
        .target(
            name: "GitHub",
            dependencies: [
                .product(name: "Exec", package: "Exec"),
                .product(name: "AIInstructions", package: "AIInstructions"),
            ],
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(
            name: "GitHubTests",
            dependencies: [
                "GitHub", .product(name: "Exec", package: "Exec"),
                .product(name: "AIInstructions", package: "AIInstructions"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
