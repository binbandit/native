// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativePolicy",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativePolicy", targets: ["NativePolicy"])
    ],
    dependencies: [.package(path: "../ApprovalAnalysis"), .package(path: "../CodeThemes")],
    targets: [
        .target(
            name: "NativePolicy", dependencies: ["ApprovalAnalysis", "CodeThemes"],
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "NativePolicyTests", dependencies: ["NativePolicy"]),
    ]
)
