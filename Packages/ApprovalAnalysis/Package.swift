// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ApprovalAnalysis",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ApprovalAnalysis", targets: ["ApprovalAnalysis"])],
    dependencies: [.package(path: "../ACP")],
    targets: [
        .target(
            name: "ApprovalAnalysis", dependencies: ["ACP"], resources: [.process("Resources")],
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "ApprovalAnalysisTests", dependencies: ["ApprovalAnalysis"]),
    ]
)
