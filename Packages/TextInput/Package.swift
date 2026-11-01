// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TextInput",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "TextInput", targets: ["TextInput"])],
    targets: [
        .target(name: "TextInput"),
        .testTarget(name: "TextInputTests", dependencies: ["TextInput"]),
    ]
)
