import ACP
import NativeHostClient

/// What `HostNotificationFeed` needs from the app besides what Usage's notifications do. `AppModel`
/// conforms.
protocol HostNotificationsAppHost: UsageNotificationsHost {
    /// The task on screen.
    var selection: SessionKey? { get }
    /// Whether this Mac has the session open, so its own engines (limits) hear what happens in it.
    func follows(_ ref: UsageSessionRef) -> Bool
    /// The client of the host the session runs on, when this Mac has it open there.
    func hostClient(of ref: UsageSessionRef) -> NativeHostClient?
}

extension AppModel: HostNotificationsAppHost {
    func follows(_ ref: UsageSessionRef) -> Bool {
        openModels(of: ref).first != nil
    }

    func hostClient(of ref: UsageSessionRef) -> NativeHostClient? {
        openModels(of: ref).compactMap(\.host?.client).first
    }

    /// The session's model and, for a subagent, its parent's, whichever the app has open.
    private func openModels(of ref: UsageSessionRef) -> [SessionModel] {
        ([ref.session] + (ref.parent.map { [$0] } ?? [])).compactMap { session(SessionKey(agent: ref.agent, id: $0)) }
    }
}
