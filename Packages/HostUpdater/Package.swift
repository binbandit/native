// swift-tools-version: 6.2
import PackageDescription

// How a standalone Native Host (a Linux run box, a Mac with only `native-host`) updates itself:
// the signed host feed, signature checks, and an atomic install with rollback. Foundation-only so
// it builds wherever the host does. See docs/releasing.md, "Remote updates".
let package = Package(
    name: "HostUpdater",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HostUpdater", targets: ["HostUpdater"])
    ],
    targets: [
        // TODO(linux): add apple/swift-crypto for Ed25519 on Linux (CryptoKit on Apple platforms),
        // with a decision record, when the host first builds there.
        .target(name: "HostUpdater"),
        .testTarget(name: "HostUpdaterTests", dependencies: ["HostUpdater"]),
    ]
)
