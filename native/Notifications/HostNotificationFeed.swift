import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import os

/// Shows the notifications Native's hosts post (docs/durability.md, "Notifications"): this Mac's own
/// host's and every paired host's, the latter named. It tells each host what the user saw and did,
/// so a notification answered or opened here clears on the user's other devices, and takes down
/// what was cleared there. Coming back after an absence, what it missed is summed up ("While you
/// were away"), never replayed one notification at a time.
final class HostNotificationFeed {
    /// A host whose notifications this Mac follows.
    private struct Host {
        let id: NativeHostProtocol.HostID
        /// What the user calls it; nil for this Mac's own host.
        let name: String?
        let client: NativeHostClient

        var isLocal: Bool { name == nil }
    }

    private(set) weak var app: (any HostNotificationsAppHost)?
    /// Sums up what a host did while Native was closed, for the window: this Mac's own host at
    /// launch, and each paired host the first time it connects in a run. `isLocal` for this Mac's.
    var onHostAway: ((AwaySummary, NativeHostProtocol.HostID, _ isLocal: Bool) -> Void)?

    private let poster: any NativeNotificationPosting
    private let activity: any AppActivity
    private let preferences: NotificationPreferences
    private var hosts: [NativeHostProtocol.HostID: Host] = [:]
    /// What's still news on each host, by id.
    private var active: [NativeHostProtocol.HostID: [Int64: HostNotification]] = [:]
    /// What this Mac shows from each host: the notification showing for each group.
    private var shown: [NativeHostProtocol.HostID: [String: Int64]] = [:]
    /// Hosts caught up with once this run, so catching up again is a reconnection.
    private var caughtUp: Set<NativeHostProtocol.HostID> = []
    /// Hosts being caught up with, and what they posted live meanwhile, which isn't missed.
    private var catchingUp: [NativeHostProtocol.HostID: Set<Int64>] = [:]
    /// What the user saw while a host was out of reach, to tell it once it's back.
    private var unsentAcknowledgements: [NativeHostProtocol.HostID: Set<Int64>] = [:]
    /// What the user did on a notification before its host connected (a click that launched Native).
    private var waitingResponses: [NativeHostProtocol.HostID: [NativeNotificationResponse]] = [:]

    private static let seenKey = "NativeHostSeenNotifications"
    private static let logger = Logger(subsystem: "Native", category: "HostNotifications")

    init(
        poster: any NativeNotificationPosting, activity: any AppActivity,
        preferences: NotificationPreferences = NotificationPreferences()
    ) {
        self.poster = poster
        self.activity = activity
        self.preferences = preferences
    }

    var isEnabled: Bool {
        HostNotificationsSwitch.isEnabled
    }

    /// Gives the feed the app to show tasks in. Opening a task is seeing what its notifications said.
    func connect(to app: AppModel) {
        self.app = app
        Task { [weak self] in
            for await selection in Observations({ app.selection }) {
                guard let self else { return }
                if let selection, activity.isActive {
                    taskOpened(selection)
                }
            }
        }
    }

    /// Whether a host this Mac follows notifies about the task itself, so the app's own path stays
    /// quiet about it.
    func covers(_ ref: UsageSessionRef) -> Bool {
        guard isEnabled, let client = app?.hostClient(of: ref) else { return false }
        return hosts.values.contains { $0.client === client }
    }

    // MARK: - Hosts

    /// Follows this Mac's own host, once its client is connected.
    func follow(_ client: NativeHostClient) async {
        guard isEnabled else { return }
        await client.addEventHandler { [weak self] event in
            await self?.receive(event, from: client, name: nil)
        }
        if let info = await client.hostInfo {
            connected(Host(id: info.hostID, name: nil, client: client))
        }
    }

    /// One of a host's events. `name` is what the user calls a paired host; nil for this Mac's own.
    func receive(_ event: NativeHostClient.Event, from client: NativeHostClient, name: String?) {
        guard isEnabled else { return }
        switch event {
        case .connection(.connected(let info)):
            connected(Host(id: info.hostID, name: name, client: client))
        case .notificationPosted(let notification):
            guard let host = host(of: client) else { return }
            remember(notification.id, on: host.id)
            catchingUp[host.id]?.insert(notification.id)
            active[host.id, default: [:]][notification.id] = notification
            present(notification, on: host)
        case .notificationsCleared(let message):
            guard let host = host(of: client) else { return }
            Self.logger.info(
                "\(message.state.rawValue, privacy: .public) \(message.ids) on \(host.id, privacy: .public)")
            takeDown(message.ids, on: host)
        default:
            break
        }
    }

    private func host(of client: NativeHostClient) -> Host? {
        hosts.values.first { $0.client === client }
    }

    private func connected(_ host: Host) {
        hosts[host.id] = host
        Task { await catchUp(host) }
    }

    /// After (re)connecting: what's still news, what was cleared elsewhere meanwhile, and what was
    /// missed, summed up.
    private func catchUp(_ host: Host) async {
        guard catchingUp[host.id] == nil else { return }
        catchingUp[host.id] = []
        defer { catchingUp[host.id] = nil }
        let isReconnection = !caughtUp.insert(host.id).inserted
        let seen = lastSeen(on: host.id)
        let list: HostNotificationList
        do {
            list = try await host.client.notifications(after: seen)
        } catch {
            Self.logger.error("Couldn't read notifications: \(error.localizedDescription, privacy: .public)")
            return
        }
        active[host.id] = Dictionary(list.active.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        if let unsent = unsentAcknowledgements.removeValue(forKey: host.id) {
            acknowledge(Array(unsent), on: host)
        }
        await reconcileShown(on: host)
        for response in waitingResponses.removeValue(forKey: host.id) ?? [] {
            perform(response, on: host)
        }
        if let latest = list.latestID {
            remember(latest, on: host.id)
        }
        // A host's first connection only sets where news starts.
        guard seen != nil else { return }
        let heardLive = catchingUp[host.id] ?? []
        let missed = list.notifications.filter { active[host.id]?[$0.id] != nil && !heardLive.contains($0.id) }
        Self.logger.info("Caught up with \(host.id, privacy: .public): \(missed.count) missed")
        if isReconnection, missed.count == 1, let only = missed.first, only.at.timeIntervalSinceNow > -60 {
            // A connection that dropped for a moment: as if it had come live.
            present(only, on: host)
        } else if !missed.isEmpty {
            summarize(missed, on: host, isLaunch: !isReconnection)
        }
    }

    /// Takes down what this Mac shows from `host` that stopped being news while it wasn't
    /// listening, including what an earlier run of Native posted, and keeps track of the rest.
    private func reconcileShown(on host: Host) async {
        let current = active[host.id] ?? [:]
        var stillShown: [String: Int64] = [:]
        var stale: [String] = []
        for notification in await poster.delivered() where notification.hostID == host.id.description {
            guard let id = notification.hostNotificationID else { continue }
            if let still = current[id] {
                stillShown[still.group] = id
            } else {
                stale.append(notification.id)
            }
        }
        shown[host.id] = stillShown
        poster.remove(stale)
    }

    // MARK: - Showing

    private func present(_ notification: HostNotification, on host: Host) {
        // Named as the sidebar names the task now: its title may have come after the host's notice.
        var named = notification
        if let ref = notification.ref, let title = app?.taskTitle(ref) {
            named.title = title
        }
        guard isWanted(named), let content = NativeNotification(named, hostID: host.id, hostName: host.name) else {
            return
        }
        if activity.isActive, let ref = notification.ref, app?.isShowing(ref) == true {
            // The user is looking at the task: seen, here and on their other devices.
            acknowledge([notification.id], on: host)
            return
        }
        shown[host.id, default: [:]][notification.group] = notification.id
        Self.logger.info(
            "Showing \(notification.kind.rawValue, privacy: .public) \(notification.id) from \(host.id, privacy: .public)"
        )
        Task { await poster.post(content) }
    }

    /// What the user asked to hear about in Settings › Notifications.
    private func isWanted(_ notification: HostNotification) -> Bool {
        switch notification.kind {
        case .permission, .question, .turnFailed:
            return preferences.notifiesNeedsYou
        case .turnFinished:
            return preferences.notifiesLongWork && (notification.duration ?? 0) >= preferences.longWorkThreshold
        case .limitReached:
            // The limits this Mac tracks itself notify about the tasks it has open, with Resume at Reset.
            guard preferences.notifiesUsageLimits, let ref = notification.ref else { return false }
            return app?.follows(ref) != true
        case .recovered:
            // Recoveries that worked show in the transcript; one that didn't leaves the task stopped.
            switch notification.recovery?.action {
            case .failed?, .paused?: return preferences.notifiesNeedsYou
            default: return false
            }
        case .unknown:
            return false
        }
    }

    /// The window's "While you were away" for a host's first connection in a run, and one
    /// notification for everything missed when the window isn't in front or the host is another Mac.
    private func summarize(_ missed: [HostNotification], on host: Host, isLaunch: Bool) {
        guard let summary = AwaySummary(notifications: missed) else { return }
        if isLaunch {
            onHostAway?(summary, host.id, host.isLocal)
        }
        guard !host.isLocal || !activity.isActive, missed.contains(where: isWanted) else { return }
        Self.logger.info("Summing up \(missed.count) notifications from \(host.id, privacy: .public)")
        Task { await poster.post(.away(summary, hostID: host.id, hostName: host.name)) }
    }

    private func takeDown(_ ids: [Int64], on host: Host) {
        let gone = Set(ids)
        for id in gone {
            active[host.id]?[id] = nil
        }
        let groups = (shown[host.id] ?? [:]).filter { gone.contains($0.value) }.map(\.key)
        for group in groups {
            shown[host.id]?[group] = nil
        }
        poster.remove(groups.map { NativeNotification.identifier(host: host.id, group: $0) })
    }

    // MARK: - What the user did

    /// The user saw these here: they come down, and their host clears them on every other client.
    private func acknowledge(_ ids: [Int64], on host: Host) {
        guard !ids.isEmpty else { return }
        takeDown(ids, on: host)
        Task {
            do {
                try await host.client.acknowledgeNotifications(ids)
            } catch {
                unsentAcknowledgements[host.id, default: []].formUnion(ids)
            }
        }
    }

    private func taskOpened(_ key: SessionKey) {
        for (hostID, notifications) in active {
            guard let host = hosts[hostID] else { continue }
            let ids = notifications.values.filter { notification in
                notification.agentID == key.agent.rawValue
                    && (notification.parentAgentSessionID ?? notification.agentSessionID) == key.id
            }
            acknowledge(ids.map(\.id), on: host)
        }
    }

    /// What the user did with one of the hosts' notifications here, from `UsageNotifications`.
    func respond(_ response: NativeNotificationResponse) {
        guard
            let hostID = response.notification.hostID.flatMap(UUID.init(uuidString:)).map(
                NativeHostProtocol.HostID.init)
        else { return }
        guard let host = hosts[hostID] else {
            waitingResponses[hostID, default: []].append(response)
            return
        }
        perform(response, on: host)
    }

    private func perform(_ response: NativeNotificationResponse, on host: Host) {
        guard let id = response.notification.hostNotificationID else { return }
        let ref = response.notification.ref
        guard !response.isDismissed else {
            acknowledge([id], on: host)
            return
        }
        guard let action = response.action.flatMap({ HostNotification.Action(rawValue: $0.rawValue) }) else {
            // The notification itself: its task.
            if let ref { app?.show(ref) }
            acknowledge([id], on: host)
            return
        }
        takeDown([id], on: host)
        Task {
            let outcome = try? await host.client.act(on: id, action, text: response.replyText)
            Self.logger.info(
                "\(action.rawValue, privacy: .public) on \(id): \(outcome?.rawValue ?? "failed", privacy: .public)")
            // What the notification couldn't do opens the task, so the user isn't left wondering.
            if outcome != .done, outcome != .alreadyAnswered, let ref {
                app?.show(ref)
            }
        }
    }

    // MARK: - Where news starts

    private func lastSeen(on host: NativeHostProtocol.HostID) -> Int64? {
        (UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Int64])?[host.description]
    }

    /// The newest notification this Mac heard of from `host`: what comes after it is news next time.
    private func remember(_ id: Int64, on host: NativeHostProtocol.HostID) {
        var seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Int64] ?? [:]
        guard id > seen[host.description] ?? -1 else { return }
        seen[host.description] = id
        UserDefaults.standard.set(seen, forKey: Self.seenKey)
    }
}
