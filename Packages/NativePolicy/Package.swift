// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativePolicy",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativePolicy", targets: ["NativePolicy"])
    ],
    targets: [
        .target(name: "NativePolicy"),
        .testTarget(name: "NativePolicyTests", dependencies: ["NativePolicy"]),
    ]
)
