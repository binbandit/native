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

    /// Restarts the host onto this app's binary now. Running turns are interrupted and resume on the
    /// new host, which says it restarted to update.
    func restartHost() async {
        await perform("restart the host") { client in
            try await client.shutdownHost(stopAgents: false, immediately: true)
        }
    }

    /// Compares builds and, for a host from an earlier Native, asks it (once per host process) to
    /// restart onto this app's binary as soon as nothing is running.
    func refreshVersionStatus() {
        guard case .connected(let info) = connection else { return }
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        versionStatus = .compare(
            appBuild: appBuild, hostBuild: info.hostInfo.build, hostVersion: info.hostInfo.version,
            workingTasks: workingTasks
        )
        guard case .hostRestartPending = versionStatus, restartRequested != info.epoch, let client else { return }
        restartRequested = info.epoch
        Task { try? await client.shutdownHost(stopAgents: false) }
    }
}
