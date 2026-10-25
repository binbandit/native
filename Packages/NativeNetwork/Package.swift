// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeNetwork",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "NativeNetwork", targets: ["NativeNetwork"])],
    dependencies: [.package(path: "../NativePolicy")],
    targets: [
        .target(name: "NativeNetwork", dependencies: ["NativePolicy"]),
        .testTarget(name: "NativeNetworkTests", dependencies: ["NativeNetwork"]),
    ]
)
