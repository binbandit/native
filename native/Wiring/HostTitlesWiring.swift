import Foundation
import NativeHostClient

/// Titles of tasks in Native's host (docs/durability.md, "Titles"). With `HostTitles` on, the host
/// writes them and the app follows, naming each task's workspace once its title lands; off, the app
/// writes them as before and the host is told not to. Connected before `AppModel.start()`, so no
/// task starts before the host knows who titles it.
enum HostTitlesWiring {
    static func connect(_ model: AppModel, to client: NativeHostClient) async {
        guard HostTitles.isEnabled else {
            return await model.titles.leaveTitlesToApp(on: client)
        }
        await model.titles.follow(client, titler: { [plugins = model.plugins] in plugins.titler }) {
            key, folder, title in
            let event = AppModel.TitleEvent(
                key: SessionKey(agent: key.agent, id: key.session), folder: folder, title: title)
            Task { await model.workspaceGotTitle(event) }
        }
    }
}
