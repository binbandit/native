import Foundation
import NativeHostClient
import NativeHostProtocol

/// Updates (`docs/durability.md`, "Updates"): the host serves this Mac's updater status to paired
/// devices, and moves onto this app's binary after Native updates.
extension DurableHost {
    /// Tells the host this Mac's update status every time the updater's changes, so devices paired
    /// with it see it (docs/releasing.md, "Remote updates"), and relays their requests back.
    func connectUpdates(_ updates: UpdateController) {
        guard self.updates !== updates else { return }
        self.updates = updates
        reporting?.cancel()
        reporting = Task { [weak self] in
            for await snapshot in Observations({ updates.snapshot }) {
                await self?.report(snapshot)
            }
        }
    }

    func report(_ snapshot: UpdateSnapshot) async {
        guard let client, case .connected = connection else { return }
        try? await client.reportUpdateStatus(HostUpdateStatus(snapshot))
    }

    /// The tasks restarting the host now would interrupt, which an update waits for: for the notice
    /// and the confirmation that names them (`hostRestartConfirmation`). An agent's own subagents go
    /// with their task.
    var interruptedByRestart: [HostSessionSummary] {
        sessions.filter { $0.holdsRestart && $0.origin != .announced }
    }

    /// Restarts the host onto this app's binary now. Running turns are interrupted and resume on the
    /// new host, which says it restarted to update. Ask first while `interruptedByRestart` has any.
    func restartHost() async {
        requestHostRestart()
        await confirmHostRestart()
    }

    /// Compares builds and, for a host from an earlier Native, asks it (once per host process) to
    /// restart onto this app's binary as soon as nothing is running.
    func refreshVersionStatus() {
        guard case .connected(let info) = connection else { return }
        let labels = Self.versionLabels(host: info.hostInfo)
        appVersionLabel = labels.app
        versionStatus = .compare(
            appBuild: AppVersion.current.build, hostBuild: info.hostInfo.build, hostVersion: labels.host,
            workingTasks: interruptedByRestart.count
        )
        guard case .hostRestartPending = versionStatus, restartRequested != info.epoch, let client else { return }
        restartRequested = info.epoch
        Task { try? await client.shutdownHost(stopAgents: false) }
    }

    /// The app's and the host's versions as the notice names them: with their build numbers when
    /// the versions read the same ("1.0 (build 512)"), as they do after a rebuild, so it never says
    /// "updated to 1.0, still running on 1.0".
    static func versionLabels(host: PeerInfo) -> (app: String, host: String) {
        let app = AppVersion.current
        guard host.version == app.version else { return (app.version, host.version) }
        return ("\(app.version) (build \(app.build))", "\(host.version) (build \(host.build))")
    }
}
