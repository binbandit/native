// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Telemetry",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NativeTelemetry", targets: ["NativeTelemetry"])
    ],
    targets: [
        .target(
            name: "NativeTelemetry",
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "NativeTelemetryTests", dependencies: ["NativeTelemetry"]),
    ]
)
