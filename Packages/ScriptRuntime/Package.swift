// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScriptRuntime",
    // Scripts run only on a host (macOS). The wire types, bindings and results build for iOS too, so
    // clients can show a run; launching the runtime is macOS only.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ScriptRuntime", targets: ["ScriptRuntime"])
    ],
    targets: [
        .target(name: "ScriptRuntime"),
        .testTarget(name: "ScriptRuntimeTests", dependencies: ["ScriptRuntime"]),
    ]
)
