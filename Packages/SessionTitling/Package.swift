// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SessionTitling",
    // iOS too: the host titles tasks, and its titles cross the host protocol to every client. The
    // on-device model needs macOS 26 or iOS 26 and is checked where it's used.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SessionTitling", targets: ["SessionTitling"])
    ],
    dependencies: [
        .package(path: "../AIInstructions")
    ],
    targets: [
        .target(
            name: "SessionTitling", dependencies: [.product(name: "AIInstructions", package: "AIInstructions")],
            // Optimize infrequent operations for size; the app and streaming path stay at -O.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .testTarget(name: "SessionTitlingTests", dependencies: ["SessionTitling"], resources: [.copy("Fixtures")]),
    ]
)
