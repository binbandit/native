// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProjectActions",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ProjectActions", targets: ["ProjectActions"])
    ],
    targets: [
        .target(name: "ProjectActions"),
        .testTarget(
            name: "ProjectActionsTests",
            dependencies: ["ProjectActions"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
