import Foundation

/// How an app and the host it connects to compare. After an update the host keeps running the old
/// binary until its tasks finish (`docs/durability.md`, "Updates"); opening an older copy of Native
/// meets a newer host. Either way both sides say so instead of failing quietly.
public enum HostVersionStatus: Equatable, Sendable {
    case matched
    /// The host is from an earlier Native. It restarts onto this version once nothing is running.
    case hostRestartPending(hostVersion: String, workingTasks: Int)
    /// The host is newer than this app, so this app should update.
    case appOutdated(hostVersion: String)

    /// Compares build numbers (`CFBundleVersion`, the same for the app and its embedded host).
    /// `workingTasks` is what the host is running now. A build that isn't a number counts as older
    /// than this app, so the app's own host always wins.
    public static func compare(appBuild: String, hostBuild: String, hostVersion: String, workingTasks: Int) -> Self {
        guard appBuild != hostBuild else { return .matched }
        if let app = Int(appBuild), let host = Int(hostBuild), host > app {
            return .appOutdated(hostVersion: hostVersion)
        }
        return .hostRestartPending(hostVersion: hostVersion, workingTasks: workingTasks)
    }
}
