// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Undo",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Undo", targets: ["Undo"])
    ],
    targets: [
        .target(name: "Undo"),
        .testTarget(name: "UndoTests", dependencies: ["Undo"]),
    ]
)
