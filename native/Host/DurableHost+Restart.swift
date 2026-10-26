import NativeHostClient

extension DurableHost {
    /// Only this channel's local host is eligible, including its session-only fallback. Paired
    /// hosts and agents running in the app must never be substituted for it.
    var canRequestHostRestart: Bool {
        placement.usesHost && client != nil && !manualRestart.state.isBusy
    }

    func requestHostRestart() {
        guard canRequestHostRestart else { return }
        manualRestart.request()
    }

    func cancelHostRestart() {
        manualRestart.cancel()
    }

    func confirmHostRestart(whenIdle: Bool = false) async {
        guard placement.usesHost, let client else {
            manualRestart.cancel()
            return
        }
        await manualRestart.restart(using: client, whenIdle: whenIdle)
    }
}
