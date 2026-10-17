// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodeThemes",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CodeThemes", targets: ["CodeThemes"]),
    ],
    targets: [
        .target(name: "CodeThemes"),
        .testTarget(name: "CodeThemesTests", dependencies: ["CodeThemes"]),
    ]
)
