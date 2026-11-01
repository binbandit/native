// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProjectNames",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ProjectNames", targets: ["ProjectNames"])],
    targets: [
        .target(name: "ProjectNames"),
        .testTarget(name: "ProjectNamesTests", dependencies: ["ProjectNames"]),
    ]
)
