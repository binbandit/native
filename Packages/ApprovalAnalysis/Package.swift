// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ApprovalAnalysis",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ApprovalAnalysis", targets: ["ApprovalAnalysis"])],
    targets: [
        .target(name: "ApprovalAnalysis", resources: [.process("Resources")]),
        .testTarget(name: "ApprovalAnalysisTests", dependencies: ["ApprovalAnalysis"]),
    ]
)
