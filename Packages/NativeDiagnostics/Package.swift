// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeDiagnostics",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "NativeDiagnostics", targets: ["NativeDiagnostics"])],
    dependencies: [.package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.30.2")],
    targets: [
        .target(name: "NativeDiagnostics", dependencies: [.product(name: "Sentry", package: "sentry-cocoa")]),
        .testTarget(name: "NativeDiagnosticsTests", dependencies: ["NativeDiagnostics"]),
    ]
)
