import Foundation
import NativeHostProtocol

/// How this host gets updated, supplied by the platform layer (`NativeHostMac.MacHostUpdates`), so
/// the core decides who may install and when without knowing bundles or feeds.
public struct HostUpdateEnvironment: Sendable {
    public var provider: HostUpdateStatus.Provider
    public var current: HostUpdateStatus.Build
    /// Why updates are off, for provider `none`.
    public var unavailableReason: String?
    /// Provider `app`: opens Native hidden to install its update and quit, for when no app is connected.
    public var openAppToInstall: (@Sendable () async throws -> Void)?
    /// Provider `app`: this host's build as it is on disk now. An app update replaces the bundle
    /// under the running host; once this differs from `current.build`, the host restarts onto it.
    public var installedBuild: (@Sendable () -> String?)?
    /// Provider `standalone`.
    public var selfUpdater: (any HostSelfUpdater)?
    /// How often a standalone host checks its feed on its own.
    public var checkInterval: Duration

    public init(
        provider: HostUpdateStatus.Provider, current: HostUpdateStatus.Build, unavailableReason: String? = nil,
        openAppToInstall: (@Sendable () async throws -> Void)? = nil, installedBuild: (@Sendable () -> String?)? = nil,
        selfUpdater: (any HostSelfUpdater)? = nil, checkInterval: Duration = .seconds(24 * 3600)
    ) {
        self.provider = provider
        self.current = current
        self.unavailableReason = unavailableReason
        self.openAppToInstall = openAppToInstall
        self.installedBuild = installedBuild
        self.selfUpdater = selfUpdater
        self.checkInterval = checkInterval
    }

    /// Nothing updates this host (a development build, or a binary the updater didn't install).
    public static func none(current: HostUpdateStatus.Build, reason: String) -> Self {
        HostUpdateEnvironment(provider: .none, current: current, unavailableReason: reason)
    }
}

/// A standalone host's own updater (`Packages/HostUpdater` on a Mac). It only ever installs what
/// its own check found in its own signed feed.
public protocol HostSelfUpdater: Sendable {
    /// Checks the feed and downloads, verifies and stages a newer build if there is one; nil when
    /// this host is current.
    func checkAndStage() async throws -> HostUpdateStatus.Release?
    /// Points the host at a staged build. The host then exits for its supervisor to start it.
    func activate(build: String) throws
    /// The last automatic rollback, if any.
    func lastRollback() -> HostUpdateStatus.Rollback?
}
