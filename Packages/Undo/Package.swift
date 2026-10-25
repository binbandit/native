// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Undo",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Undo", targets: ["Undo"])
    ],
    targets: [
        .target(
            name: "Undo",
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "UndoTests", dependencies: ["Undo"]),
    ]
)
