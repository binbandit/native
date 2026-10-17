// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitHub",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GitHub", targets: ["GitHub"]),
    ],
    targets: [
        .target(name: "GitHub"),
        .testTarget(
            name: "GitHubTests",
            dependencies: ["GitHub"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
