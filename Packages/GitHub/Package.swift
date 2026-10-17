// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitHub",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GitHub", targets: ["GitHub"])
    ],
    dependencies: [
        .package(path: "../Exec")
    ],
    targets: [
        .target(name: "GitHub", dependencies: [.product(name: "Exec", package: "Exec")]),
        .testTarget(
            name: "GitHubTests",
            dependencies: ["GitHub", .product(name: "Exec", package: "Exec")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
