import Exec
import Foundation
import HostUpdater
import NativeHost
import NativeHostProtocol

/// How a Mac host is updated, read from where it runs (docs/releasing.md, "Remote updates"):
/// inside Native.app it's the app's updater (`app`); under `~/.native/host/versions/<build>/` it
/// updates itself (`standalone`); anything else, and every development build, can't (`none`).
public enum MacHostUpdates {
    /// The standalone host's home: its versions, the `native-host` symlink and the update ledger.
    public static let standaloneRoot = FileManager.default.homeDirectoryForCurrentUser.appending(
        path: ".native/host", directoryHint: .isDirectory)

    public static func environment(location: HostLocation, bundle: Bundle = .main) -> HostUpdateEnvironment {
        let info = bundle.infoDictionary ?? [:]
        let channel = info["NativeChannel"] as? String ?? (location.channel.isEmpty ? "stable" : location.channel)
        let current = HostUpdateStatus.Build(
            version: info["CFBundleShortVersionString"] as? String ?? "0", build: info["CFBundleVersion"] as? String ?? "0",
            channel: channel)
        if location.isDevelopment {
            return .none(current: current, reason: "Updates are off in development builds.")
        }
        if let app = enclosingApp(of: bundle) {
            let plist = bundle.bundleURL.appending(path: "Contents/Info.plist")
            return HostUpdateEnvironment(
                provider: .app, current: current,
                openAppToInstall: { try await openToInstall(app) },
                installedBuild: { buildOnDisk(plist) })
        }
        let executable = (bundle.executableURL ?? URL(filePath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        let versions = standaloneRoot.appending(path: "versions").resolvingSymlinksInPath().path(percentEncoded: false)
        if executable.path(percentEncoded: false).hasPrefix(versions + "/"),
            let updater = StandaloneHostUpdater(info: info, root: standaloneRoot, runningBuild: current.build)
        {
            return HostUpdateEnvironment(provider: .standalone, current: current, selfUpdater: updater)
        }
        return .none(current: current, reason: HostUpdateError.notInstalled.localizedDescription)
    }

    /// `Native.app`, when this host is the helper at `Native.app/Contents/Library/LoginItems/`.
    static func enclosingApp(of bundle: Bundle) -> URL? {
        let loginItems = bundle.bundleURL.deletingLastPathComponent()
        guard loginItems.path(percentEncoded: false).hasSuffix("Contents/Library/LoginItems/") else { return nil }
        let app = loginItems.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.pathExtension == "app" ? app : nil
    }

    /// The build in the bundle on disk now, not the one loaded at launch (`Bundle` caches it).
    static func buildOnDisk(_ plist: URL) -> String? {
        guard let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleVersion"] as? String
    }

    /// Opens Native hidden, without stealing focus, in the mode where it installs its update
    /// without relaunching and quits (`UpdateController.installAndQuitKey`).
    private static func openToInstall(_ app: URL) async throws {
        let result = try await LocalCommandRunner().run(
            Command(
                "/usr/bin/open", ["-g", "-j", app.path(percentEncoded: false), "--args", "-NativeInstallUpdateAndQuit", "YES"],
                environment: ProcessInfo.processInfo.environment, timeout: .seconds(30)))
        guard result.succeeded else { throw CommandError.unavailable("Couldn't open Native: \(result.errorOutput)") }
    }
}

/// A standalone host's updater: `Packages/HostUpdater`'s signed feed and atomic install.
public struct StandaloneHostUpdater: HostSelfUpdater {
    public let installer: HostBinaryInstaller
    let source: HostUpdateSource
    let runningBuild: String

    /// Nil when the host carries no feed or key (the embedded Info.plist's `NativeHostFeedURL` and
    /// `SUPublicEDKey`), so it has nothing it could trust.
    public init?(info: [String: Any], root: URL, runningBuild: String) {
        guard let feed = (info["NativeHostFeedURL"] as? String).flatMap(URL.init(string:)),
            let key = (info["SUPublicEDKey"] as? String).flatMap({ try? UpdateSigningKey(base64: $0) })
        else { return nil }
        installer = HostBinaryInstaller(root: root, key: key)
        source = HostUpdateSource(feedURL: feed, key: key)
        self.runningBuild = runningBuild
    }

    public func checkAndStage() async throws -> HostUpdateStatus.Release? {
        let feed = try await source.latest()
        guard feed.isNewer(than: runningBuild) else { return nil }
        if !installer.isStaged(feed.build) {
            try await source.download(feed, into: installer)
        }
        let size = feed.asset(for: .current, arch: .current)?.size
        return HostUpdateStatus.Release(
            version: feed.version, build: feed.build, notes: feed.notes, releaseNotesURL: feed.releaseNotesURL,
            date: feed.date, size: size)
    }

    public func activate(build: String) throws {
        try installer.activate(build: build)
    }

    public func lastRollback() -> HostUpdateStatus.Rollback? {
        installer.ledger().lastRollback.map { HostUpdateStatus.Rollback(from: $0.from, to: $0.to, at: $0.at) }
    }
}

extension StandaloneHostUpdater {
    /// For a build on trial after an update: shakes hands with the host's own socket, the way a
    /// client would, and keeps the build once that works. False if it didn't within `deadline`; the
    /// host should then exit so the supervisor tries again (and the updater rolls back).
    public func confirmWhenServing(at location: HostLocation, deadline: Duration = .seconds(60)) async -> Bool {
        let end = ContinuousClock.now + deadline
        while ContinuousClock.now < end {
            if let handshake = try? await Self.handshake(location), handshake.hostInfo.build == runningBuild,
                (try? installer.confirm(runningBuild: runningBuild)) != nil
            {
                return true
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    private static func handshake(_ location: HostLocation) async throws -> FrozenHandshake {
        let peer = JSONRPCPeer(
            channel: ByteChannel.socket(try UnixSocket.connect(to: location.socketPath), label: "self-check"),
            label: "self-check"
        ) { _ in }
        peer.start()
        defer { peer.close() }
        return try await peer.request(
            HostProtocol.Method.initialize,
            InitializeParams(clientInfo: PeerInfo(name: "native-host self-check", version: "", build: "")),
            as: FrozenHandshake.self)
    }
}
