// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeDataLifecycle",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativeDataLifecycle", targets: ["NativeDataLifecycle"])
    ],
    dependencies: [.package(path: "../NativePolicy")],
    targets: [
        .target(name: "NativeDataLifecycle", dependencies: ["NativePolicy"]),
        .testTarget(
            name: "NativeDataLifecycleTests", dependencies: ["NativeDataLifecycle"], resources: [.copy("Fixtures")]),
    ]
)
