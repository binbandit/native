/// Builder/operator activity is deliberately outside runtime service permissions.
public struct BuildNetworkInventory: Sendable {
    public let location = NetworkInventory.Location.offMachine
    public let id: String
    public let owner: String
    public let destinationSource: String
    public let trigger: String
    public let payload: String
    public let redirects: String
    public let offline: String

    public static let entries: [BuildNetworkInventory] = [
        .init(
            id: "build.swift", owner: "native.xcodeproj; Packages/*/Package.swift",
            destinationSource: "resolved SwiftPM sources and binary artifacts", trigger: "package resolution",
            payload: "source and binary dependencies", redirects: "toolchain owned",
            offline: "prestage exact dependencies"),
        .init(
            id: "build.runtime",
            owner: "scripts/build-script-runtime.sh; Runtime/ScriptRuntime/scripts/build-v8-sandbox.py",
            destinationSource: "pinned Rust, Cargo, V8 and ICU inputs", trigger: "runtime build",
            payload: "toolchain and source archives", redirects: "builder owned", offline: "prestage verified inputs"),
        .init(
            id: "build.terminal", owner: "scripts/build-libghostty.sh",
            destinationSource: "pinned Zig, Ghostty and hashed dependencies", trigger: "terminal build",
            payload: "toolchain and source", redirects: "builder owned", offline: "prestage verified inputs"),
        .init(
            id: "build.catalog", owner: "scripts/adapters/lockfile.py; scripts/plugins/build-index.py",
            destinationSource: "explicit registry and local signing inputs", trigger: "maintainer generation",
            payload: "package metadata and signed catalog", redirects: "tool owned", offline: "local signing works"),
        .init(
            id: "release.publish", owner: "scripts/release/; scripts/companion/",
            destinationSource: "operator GitHub, Apple and Sentry configuration", trigger: "release publication",
            payload: "archives, feeds, signatures and symbols", redirects: "release tool owned",
            offline: "publication unavailable"),
        .init(
            id: "operator.development", owner: "scripts/dev/; scripts/ci/; scripts/host/",
            destinationSource: "explicit build, test, SSH and install targets", trigger: "operator command",
            payload: "build/test/install artifacts", redirects: "operator tool owned",
            offline: "requires supplied tools/fixtures"),
    ]
}
