// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Search",
    // iOS too: clients query a host's index, and the index itself is plain system SQLite.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Search", targets: ["Search"])
    ],
    dependencies: [
        // Live sessions are indexed straight from the ACP transcript.
        .package(path: "../ACP")
    ],
    targets: [
        .target(
            name: "Search",
            dependencies: [.product(name: "ACP", package: "ACP")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "SearchTests",
            dependencies: ["Search", .product(name: "ACP", package: "ACP")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
