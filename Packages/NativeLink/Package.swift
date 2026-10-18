// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeLink",
    // The phone and iPad pair and connect with this; the Mac's host serves it.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        /// Pairing, the end-to-end authenticated transport (Noise over TCP), the host's gateway and
        /// the device side's connector. No UI.
        .library(name: "NativeLink", targets: ["NativeLink"])
    ],
    dependencies: [
        .package(path: "../NativeHost")
    ],
    targets: [
        .target(
            name: "NativeLink",
            dependencies: [.product(name: "NativeHostClient", package: "NativeHost")]
        ),
        .testTarget(
            name: "NativeLinkTests",
            dependencies: ["NativeLink", .product(name: "NativeHostClient", package: "NativeHost")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
