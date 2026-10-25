// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeSetup",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativeSetup", targets: ["NativeSetup"])
    ],
    targets: [
        .target(
            name: "NativeSetup",
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "NativeSetupTests", dependencies: ["NativeSetup"]),
    ]
)
