// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TaskList",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TaskList", targets: ["TaskList"])
    ],
    targets: [
        .target(name: "TaskList"),
        .testTarget(name: "TaskListTests", dependencies: ["TaskList"]),
    ]
)
