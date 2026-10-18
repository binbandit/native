// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeSetup",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativeSetup", targets: ["NativeSetup"])
    ],
    targets: [
        .target(name: "NativeSetup"),
        .testTarget(name: "NativeSetupTests", dependencies: ["NativeSetup"]),
    ]
)
