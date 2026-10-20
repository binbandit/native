import ACP
import Foundation
import NativeHostProtocol

// The host itself: its activity journal, updates, plugins, and stopping it.
extension NativeHostClient {
    /// What happened on the host since `after` (an activity id), for "while you were away".
    public func activity(after: Int64? = nil, limit: Int = 200) async throws -> [ActivityEntry] {
        try await call(HostProtocol.Method.listActivity, ListActivityParams(after: after, limit: limit))
    }

    // MARK: - Updates

    public func updateStatus() async throws -> HostUpdateStatus {
        try await call(HostProtocol.Method.updateStatus, EmptyMessage())
    }

    public func checkForUpdate() async throws -> HostUpdateStatus {
        try await call(HostProtocol.Method.updateCheck, EmptyMessage())
    }

    /// Installs the update the host found: `.idle` waits for running tasks, `.now` interrupts them
    /// (send it only after the user chose to). Needs the manage-host grant.
    public func installUpdate(_ when: HostUpdateStatus.When) async throws -> HostUpdateStatus {
        try await call(HostProtocol.Method.updateInstall, HostUpdateInstallParams(when: when))
    }

    /// For the Mac app: its updater's status, which the host serves to every client as its own.
    public func reportUpdateStatus(_ status: HostUpdateStatus) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.updateReport, HostUpdateStatusMessage(status: status))
    }

    // MARK: - Plugins

    /// The plugins installed on the host. `PluginAssets` fetches and caches their files.
    public func plugins() async throws -> [HostPlugin] {
        try await call(HostProtocol.Method.listPlugins, EmptyMessage())
    }

    /// Turns a plugin on or off for everyone using the host; paired devices need the grant.
    public func setPluginEnabled(_ pluginID: String, _ isEnabled: Bool) async throws -> [HostPlugin] {
        try await call(
            HostProtocol.Method.setPluginEnabled, SetPluginEnabledParams(pluginID: pluginID, isEnabled: isEnabled))
    }

    public func pluginAsset(_ params: PluginAssetParams) async throws -> PluginAsset {
        try await call(HostProtocol.Method.pluginAsset, params)
    }

    // MARK: - Stopping

    /// Stops the host and its agents (`stopAgents`), or restarts it onto the binary the app
    /// carries: once it's idle, or `immediately`, interrupting turns that then resume.
    public func shutdownHost(stopAgents: Bool, immediately: Bool = false) async throws {
        do {
            let _: EmptyMessage = try await call(
                HostProtocol.Method.shutdown, ShutdownParams(stopAgents: stopAgents, immediately: immediately))
        } catch PeerError.closed {
            // The host can exit before its answer gets out; that's the request working.
        }
    }
}
