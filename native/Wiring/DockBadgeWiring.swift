import NativeAutomation
import Observation

/// Shows on the app icon how many tasks need the user, as the Dock badge setting says. Connected
/// once at launch; it writes the badge only when the number changes, so streaming turns, which
/// re-evaluate the count, never touch the Dock tile.
@MainActor
enum DockBadgeWiring {
    static func connect(
        model: AppModel,
        workflows: WorkflowRunner,
        preference: DockBadgePreference = .shared
    ) {
        Task {
            var lastApplied: Int?
            for await badgeCount in Observations({
                count(model: model, workflows: workflows, mode: preference.mode)
            }) where badgeCount != lastApplied {
                await PlatformApplication.setBadgeCount(badgeCount)
                lastApplied = badgeCount
            }
        }
    }

    /// Each listed task that needs the user counts once: a permission request, question or plan
    /// review in it or a subagent under it (what the sidebar marks), and with `.needsYouAndUnread`
    /// an unread one. Workflow runs waiting on the user add theirs, as the Workflows item counts them.
    static func count(model: AppModel, workflows: WorkflowRunner, mode: DockBadgePreference.Mode) -> Int {
        guard mode != .off else { return 0 }

        let tasks = Set(model.sessionList.map(\.id)).count { id in
            model.session(id)?.needsApproval == true || (mode == .needsYouAndUnread && model.isUnread(id))
        }
        return tasks + workflows.runs.count { $0.phase.needsUser }
    }
}
