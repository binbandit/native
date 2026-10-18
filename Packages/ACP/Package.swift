// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ACP",
    // iOS too, for the companion app: everything but launching agent processes is shared.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ACP", targets: ["ACP"])
    ],
    targets: [
        .target(name: "ACP"),
        .testTarget(name: "ACPTests", dependencies: ["ACP"]),
    ]
)
