// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppAppearance",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "AppAppearance", targets: ["AppAppearance"])],
    targets: [
        .target(
            name: "AppAppearance",
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(
            name: "AppAppearanceTests", dependencies: ["AppAppearance"],
            resources: [.copy("Fixtures/celebration-valentines-day.json")]),
    ]
)
