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
        .target(name: "NativePolicy", dependencies: ["ApprovalAnalysis", "CodeThemes"]),
        .testTarget(name: "NativePolicyTests", dependencies: ["NativePolicy"]),
    ]
)
