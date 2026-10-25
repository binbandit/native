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
        // The theme catalog, not CodeThemes: whatever reads policy (the host too) would otherwise link
        // every highlighting grammar.
        .target(
            name: "NativePolicy",
            dependencies: ["ApprovalAnalysis", .product(name: "CodeThemeCatalog", package: "CodeThemes")],
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "NativePolicyTests", dependencies: ["NativePolicy"]),
    ]
)
