import Foundation
import NativeHostProtocol

// Updating this host from any client (docs/releasing.md, "Remote updates"). Anyone authenticated may
// read the status and ask for a check; installing takes the `manageHost` grant, carries no URL or
// binary, and is journaled with the device that asked. A Mac host relays installs to Native.app's
// updater; a standalone host installs builds its own signed feed offered. Checking, staging and
// installing all need the policy's `updates` (docs/enterprise/host-policy.md).
extension HostCore {
    static func initialUpdateState(_ updates: HostUpdateEnvironment) -> HostUpdateStatus {
        switch updates.provider {
        case .app:
            HostUpdateStatus(
                provider: .app, current: updates.current, state: .idle,
                message: "Native checks for updates while it's open.")
        case .standalone:
            HostUpdateStatus(
                provider: .standalone, current: updates.current, state: .idle,
                lastRollback: updates.selfUpdater?.lastRollback())
        case .none, .unknown:
            HostUpdateStatus(
                provider: .none, current: updates.current, state: .unavailable, message: updates.unavailableReason)
        }
    }

    /// The status as `client` sees it: what installing now would interrupt, and whether it may.
    func updateStatus(for client: ClientLink) -> HostUpdateStatus {
        var status = updateState
        status.workingSessions = sessions.values.count { $0.turn != nil || $0.phase == .recovering }
        status.canInstall =
            client.grants.manageHost && status.provider != .none && status.hasInstallableUpdate && allows(.updates)
        if !allows(.updates), status.provider == .standalone {
            status.state = .unavailable
            status.message = HostPolicyDenial(HostCapability.updates.action, policy: policy).localizedDescription
        }
        return status
    }

    func publishUpdate() {
        for client in clients.values {
            client.notify(HostProtocol.Method.updateChanged, HostUpdateStatusMessage(status: updateStatus(for: client)))
        }
    }

    /// At startup: a standalone host says if its last update was rolled back, and checks its feed
    /// now and then, while the policy allows updates.
    func startUpdates() {
        let updates = configuration.updates
        guard updates.provider == .standalone, let updater = updates.selfUpdater else { return }
        if let rollback = updater.lastRollback(),
            (try? store.meta(MetaKey.journaledRollback)) != String(rollback.at.timeIntervalSince1970)
        {
            journal(
                .updateRolledBack, session: nil,
                detail: "Native Host \(rollback.from) didn't start, so the host went back to \(rollback.to)")
            try? store.setMeta(MetaKey.journaledRollback, String(rollback.at.timeIntervalSince1970))
        }
        guard allows(.updates), updateChecks == nil else { return }
        let interval = updates.checkInterval
        updateChecks = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self?.checkForUpdate()
            }
        }
    }

    /// Starts a check: the Mac app's updater for provider `app`, the host's own feed for `standalone`.
    func checkForUpdate() {
        // The policy as it is now, not as it was at the last refresh: the check reads its mirror now.
        refreshPolicy()
        guard allows(.updates) else { return }
        switch configuration.updates.provider {
        case .app:
            if let id = appUpdateClient, let app = clients[id] {
                app.notify(HostProtocol.Method.appUpdateCheck, EmptyMessage())
            }
        case .standalone:
            guard let updater = configuration.updates.selfUpdater, updateState.state != .checking else { return }
            updateState.state = .checking
            updateState.message = nil
            publishUpdate()
            updateCheck = Task {
                do {
                    let release = try await updater.checkAndStage()
                    // Revoked while it checked: what it found isn't offered or installed.
                    guard !Task.isCancelled, allows(.updates) else { return }
                    updateState.available = release
                    updateState.state = release == nil ? .upToDate : .ready
                    updateState.lastChecked = .now
                    publishUpdate()
                    if let pending = updateState.pendingInstall, release != nil {
                        applyStandaloneUpdate(pending)
                    }
                } catch {
                    guard !Task.isCancelled, allows(.updates) else { return }
                    updateState.lastChecked = .now
                    updateFailed(error)
                }
            }
        case .none, .unknown:
            break
        }
    }

    /// The policy no longer allows updates: the timer and any check stop, and nothing waits to be
    /// installed. A build already staged stays on disk, unused.
    func stopUpdates() {
        updateChecks?.cancel()
        updateChecks = nil
        updateCheck?.cancel()
        updateCheck = nil
        updateState.pendingInstall = nil
        // A restart already asked for still happens, onto this build.
        pendingActivation = nil
        if updateState.provider == .standalone, updateState.state == .checking || updateState.state == .installing {
            updateState.state = .idle
        }
    }

    /// Installs the update the host already knows about, once nothing is running or now.
    func installUpdate(_ when: HostUpdateStatus.When, by client: ClientLink) throws {
        try require(.updates)
        guard client.grants.manageHost else { throw HostError.notAuthorized("install updates") }
        guard updateState.provider != .none else {
            throw HostError.updateUnavailable(updateState.message ?? "This host can't update itself.")
        }
        guard let release = updateState.available, updateState.hasInstallableUpdate, when != .unknown else {
            throw HostError.updateUnavailable("There's no update to install. Check for updates first.")
        }
        let timing = when == .now ? "now, interrupting running tasks" : "when its tasks finish"
        journal(
            .updateRequested, session: nil,
            detail: "\(client.info?.name ?? "A device") asked to install Native \(release.version) \(timing)")
        updateState.pendingInstall = when
        publishUpdate()
        switch updateState.provider {
        case .app:
            if let id = appUpdateClient, let app = clients[id] {
                app.notify(HostProtocol.Method.appUpdateInstall, HostUpdateInstallParams(when: when))
            } else if let open = configuration.updates.openAppToInstall {
                // Native installs its update without relaunching and quits; the host then sees its
                // bundle change on disk (`restartIfReplacedOnDisk`).
                Task {
                    do { try await open() } catch { updateFailed(error) }
                }
            }
        case .standalone:
            if updateState.state == .ready {
                applyStandaloneUpdate(when)
            } else {
                checkForUpdate()
            }
        case .none, .unknown:
            break
        }
    }

    /// The Mac app's updater status, served as this host's own.
    func receiveUpdateReport(_ status: HostUpdateStatus, from client: ClientLink) throws {
        guard client.grants.isLocal else { throw HostError.notAuthorized("report this Mac's update status") }
        guard configuration.updates.provider == .app else { return }
        appUpdateClient = client.id
        var status = status
        status.provider = .app
        // A device's request stays pending until the app's updater takes it on.
        status.pendingInstall = status.pendingInstall ?? updateState.pendingInstall
        updateState = status
        publishUpdate()
    }

    /// Provider `app`: the update replaced the bundle under this running host, so restart onto it,
    /// now if a device asked for that, otherwise once nothing is running.
    func restartIfReplacedOnDisk() {
        guard configuration.updates.provider == .app, let installed = configuration.updates.installedBuild?(),
            installed != configuration.updates.current.build
        else { return }
        if updateState.pendingInstall == .now {
            exitForRestart()
        } else if !isRestartingWhenIdle {
            isRestartingWhenIdle = true
            exitIfIdleForRestart()
        }
    }

    private func applyStandaloneUpdate(_ when: HostUpdateStatus.When) {
        guard allows(.updates), let build = updateState.available?.build else { return }
        pendingActivation = build
        updateState.state = .installing
        publishUpdate()
        if when == .now {
            exitForRestart()
        } else {
            isRestartingWhenIdle = true
            exitIfIdleForRestart()
        }
    }

    func updateFailed(_ error: any Error) {
        updateState.state = .failed
        updateState.message = error.localizedDescription
        updateState.pendingInstall = nil
        publishUpdate()
    }
}
