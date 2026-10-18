// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Skills",
    // iOS too: the inventory and switches are read on the host and shown on every client.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Skills", targets: ["Skills"])
    ],
    dependencies: [
        // git runs through a `CommandRunner`, so installs run on whichever host owns the files.
        .package(path: "../Exec")
    ],
    targets: [
        .target(name: "Skills", dependencies: [.product(name: "Exec", package: "Exec")]),
        .testTarget(
            name: "SkillsTests",
            dependencies: ["Skills", .product(name: "Exec", package: "Exec")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
