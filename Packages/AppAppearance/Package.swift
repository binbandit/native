// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppAppearance",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "AppAppearance", targets: ["AppAppearance"])],
    targets: [
        .target(name: "AppAppearance"),
        .testTarget(name: "AppAppearanceTests", dependencies: ["AppAppearance"]),
    ]
)
