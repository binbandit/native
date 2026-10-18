// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeCommands",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativeCommands", targets: ["NativeCommands"])
    ],
    targets: [
        .target(name: "NativeCommands"),
        .testTarget(name: "NativeCommandsTests", dependencies: ["NativeCommands"]),
    ]
)
