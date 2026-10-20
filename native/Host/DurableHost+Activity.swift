import Foundation
import NativeHostClient
import NativeHostProtocol

/// The host process changed under a live connection: it crashed and launchd started it again, it
/// restarted onto a new build, or Native started its attached host again.
struct HostRestart: Equatable {
    let at: Date
    /// How the previous run ended, when the host said.
    var ending: ActivityEntry.RunEnding?
    /// Tasks the new host picked up again.
    var resumed: Int

    init(at: Date, entries: [ActivityEntry]) {
        self.at = at
        ending = entries.last { $0.kind == .hostStarted }?.previousRun
        resumed =
            Set(
                entries.filter { $0.kind == .recovered && $0.recovery?.cause != .agentStopped }.compactMap(\.sessionID)
            ).count
    }

    /// "Native's background host stopped unexpectedly and started again at 2:14 PM. It resumed 2 tasks."
    var sentence: String {
        let time = DSFormat.time(at, now: .now)
        let what =
            switch ending {
            case .crashed: "Native's background host stopped unexpectedly and started again at \(time)."
            case .updated: "Native's background host restarted at \(time) to update."
            default: "Native's background host restarted at \(time)."
            }
        let resumedTasks =
            switch resumed {
            case 0: "Nothing was running, so nothing was interrupted."
            case 1: "It resumed the task that was working."
            default: "It resumed the \(resumed) tasks that were working."
            }
        return "\(what) \(resumedTasks)"
    }
}

/// The activity journal (`docs/durability.md`, "While you were away"): the app remembers, per host,
/// the last entry it showed, and on its first connection of a run sums up everything after it.
extension DurableHost {
    /// How this connection relates to the ones before it in this run.
    enum Reconnection {
        /// The first connection since Native opened: whatever happened since the last one is news.
        case launch
        /// The same host process, after a dropped connection.
        case sameHost
        /// A new host process: it crashed, updated or was started again.
        case newHost
    }

    private static let seenKey = "NativeHostSeenActivity"

    /// Reads the journal since the last entry this app saw on `host` and, depending on how the app
    /// got here, sums it up as "while you were away", explains a host restart, or just catches up.
    func readActivity(from client: NativeHostClient, host: HostInfo, reconnection: Reconnection) async {
        let seen = lastSeen(on: host.hostID)
        guard let entries = try? await Self.activity(after: seen, from: client) else { return }
        if let last = entries.last {
            remember(last.id, on: host.hostID)
        } else if seen == nil {
            // A host's first connection only sets the baseline: there's no "away" before it.
            remember(0, on: host.hostID)
        }
        guard seen != nil else { return }
        switch reconnection {
        case .launch:
            away = AwaySummary(entries: entries, sessions: sessions)
        case .newHost:
            showRestart(HostRestart(at: .now, entries: entries))
        case .sameHost:
            break
        }
    }

    /// An entry that arrived live: the user saw it happen, so it's not news next launch.
    func noteSeen(_ entry: ActivityEntry) {
        guard case .connected(let info) = connection else { return }
        remember(entry.id, on: info.hostID)
    }

    func dismissAway() {
        away = nil
    }

    /// Takes one task out of the summary once the user opened it; the summary goes when it's empty.
    func removeAwayItem(_ id: HostSessionID) {
        away?.items.removeAll { $0.id == id }
        if away?.items.isEmpty == true {
            away = nil
        }
    }

    func dismissRestart() {
        restart = nil
    }

    private func showRestart(_ note: HostRestart) {
        restart = note
        // A quiet note in the status bar for a while, then it's history.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            if self?.restart == note { self?.restart = nil }
        }
    }

    private func lastSeen(on host: NativeHostProtocol.HostID) -> Int64? {
        let seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Int64]
        return seen?[host.description]
    }

    private func remember(_ id: Int64, on host: NativeHostProtocol.HostID) {
        var seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Int64] ?? [:]
        guard id > seen[host.description] ?? -1 else { return }
        seen[host.description] = id
        UserDefaults.standard.set(seen, forKey: Self.seenKey)
    }

    /// Every entry after `id`, a page at a time; a long absence can leave more than one page.
    private static func activity(after id: Int64?, from client: NativeHostClient) async throws -> [ActivityEntry] {
        var entries: [ActivityEntry] = []
        let page = 500
        while entries.count < 5 * page {
            let next = try await client.activity(after: entries.last?.id ?? id, limit: page)
            entries += next
            if next.count < page { break }
        }
        return entries
    }
}
