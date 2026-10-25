// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PluginCatalog",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "PluginCatalog", targets: ["PluginCatalog"])],
    dependencies: [.package(path: "../NativePolicy")],
    targets: [
        .target(name: "PluginCatalog", dependencies: [.product(name: "NativePolicy", package: "NativePolicy")]),
        .testTarget(name: "PluginCatalogTests", dependencies: ["PluginCatalog"]),
    ]
)
