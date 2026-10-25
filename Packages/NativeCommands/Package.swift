// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeCommands",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativeCommands", targets: ["NativeCommands"])
    ],
    targets: [
        .target(
            name: "NativeCommands",
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "NativeCommandsTests", dependencies: ["NativeCommands"]),
    ]
)
