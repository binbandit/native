// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PluginCatalog",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "PluginCatalog", targets: ["PluginCatalog"])],
    targets: [
        .target(name: "PluginCatalog"),
        .testTarget(name: "PluginCatalogTests", dependencies: ["PluginCatalog"]),
    ]
)
