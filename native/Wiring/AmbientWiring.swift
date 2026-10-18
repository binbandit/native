import SwiftUI

/// Wires the ambient features (status bar, keep awake, sounds) to the app model, so `NativeApp`
/// only holds them and `RootView` only shows the bar.
enum AmbientWiring {
    /// The status bar's items. Kept minimal by default: what's urgent (limits, tasks needing you)
    /// and what the reference app shows (keep awake, memory and CPU); the rest is a right-click away.
    static func statusBar(model: AppModel, keepAwake: KeepAwakeController) -> StatusBarRegistry {
        let registry = StatusBarRegistry()
        registry.register(LimitsStatusItem(statuses: {
            model.agents.compactMap { BuiltInPlugins.usage.limits.limitStatus(for: $0.agent.id) }
        }))
        registry.register(TasksStatusItem(source: model))
        registry.register(KeepAwakeStatusItem(controller: keepAwake))
        registry.register(ResourcesStatusItem(source: model))
        registry.register(MCPStatusItem(model: model), isVisibleByDefault: false)
        return registry
    }

    /// Keeps the Mac awake for working tasks, and tells sounds which task is on screen.
    static func connect(model: AppModel, keepAwake: KeepAwakeController) {
        keepAwake.follow {
            KeepAwakeActivity(workingAgents: model.statusBarTasks.count { $0.status == .working })
        }
        NotificationSounds.shared.isViewing = { [weak model] context in
            guard let model, let id = context.parentID ?? context.sessionID else { return false }
            // A subagent counts as viewed when its parent is on screen.
            return model.selection == SessionKey(agent: context.agent, id: id)
        }
    }
}
