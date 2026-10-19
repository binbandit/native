// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Modes",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Modes", targets: ["Modes"])
    ],
    dependencies: [
        .package(path: "../ACP")
    ],
    targets: [
        .target(name: "Modes", dependencies: [.product(name: "ACP", package: "ACP")]),
        .testTarget(name: "ModesTests", dependencies: ["Modes", .product(name: "ACP", package: "ACP")]),
    ]
)
