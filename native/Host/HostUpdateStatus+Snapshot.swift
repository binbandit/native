import NativeHostProtocol

extension HostUpdateStatus {
    /// Native.app's updater status, as the host serves it to paired devices.
    init(_ snapshot: UpdateSnapshot) {
        self.init(
            provider: .app,
            current: Build(
                version: snapshot.currentVersion, build: snapshot.currentBuild, channel: snapshot.channel.rawValue),
            state: State(rawValue: snapshot.phase.rawValue) ?? .unknown,
            available: snapshot.available.map { release in
                Release(
                    version: release.version, build: release.build, notes: release.notes,
                    releaseNotesURL: snapshot.releaseNotesURL, date: release.date, size: release.size.map { Int($0) },
                    critical: release.isCritical)
            },
            progress: snapshot.progress,
            message: snapshot.message,
            lastChecked: snapshot.lastChecked,
            pendingInstall: snapshot.pendingInstall.map { $0 == .now ? .now : .idle },
            canInstall: snapshot.canInstall
        )
    }
}
