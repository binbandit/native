// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Exec",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Exec", targets: ["Exec"]),
    ],
    targets: [
        .target(name: "Exec"),
        .testTarget(name: "ExecTests", dependencies: ["Exec"]),
    ]
)
