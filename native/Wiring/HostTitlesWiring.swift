import Foundation
import NativeHostClient
import NativeLink

/// Titles of tasks in Native's hosts (docs/durability.md, "Titles"). A host that titles its tasks
/// writes them with no app attached, and the app follows, naming each task's workspace once its
/// title lands. Who titles is chosen per host:
///
/// - This Mac's own host, by `HostTitles`: on, the host titles; off (the default), the app titles
///   as before and tells the host not to. Connected before `AppModel.start()`, so no task starts
///   before the host knows who titles it.
/// - A paired host, whatever `HostTitles` says: the Mac that started a task there may be asleep
///   when the task needs its name. Only a pairing allowed to manage the host configures it; one
///   without that grant leaves the host's configuration alone, and the app titles the tasks it
///   starts there as before.
enum HostTitlesWiring {
    static func connect(_ model: AppModel, to client: NativeHostClient) async {
        guard HostTitles.isEnabled else {
            return await model.titles.leaveTitlesToApp(on: client)
        }
        await follow(client, for: model)
    }

    /// For each new client of a paired host (`AppModel.hostConnected`), before any session opens
    /// on it and before an earlier pairing's tasks move to it.
    static func connect(_ model: AppModel, toPaired host: RemoteHost) async {
        guard let client = host.client else { return }
        if host.paired.grants.manageHost {
            // Until the pairing is replaced, removed or ended: its client stops for good then.
            await follow(client, for: model) { [weak model] in
                model?.hosts.all.contains { $0.client === client } == true
            }
        }
        // The tasks an earlier pairing of this host followed: the new one has taken those the host
        // still has, if it follows at all, and the app titles the rest again.
        model.titles.unlinkTasks(on: model.hosts.retiredClients(of: host).map(\.client))
    }

    private static func follow(
        _ client: NativeHostClient, for model: AppModel,
        while isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }
    ) async {
        await model.titles.follow(client, titler: { [plugins = model.plugins] in plugins.titler }, while: isCurrent) {
            key, folder, title in
            let event = AppModel.TitleEvent(
                key: SessionKey(agent: key.agent, id: key.session), folder: folder, title: title)
            Task { await model.workspaceGotTitle(event) }
        }
    }
}
