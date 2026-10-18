import NativeAutomation
import Observation

/// Keeps the app icon's badge aligned with work awaiting the user and is connected once at launch.
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

    /// Counts distinct listed tasks needing approval, optionally unread tasks, and workflow runs waiting on the user.
    static func count(model: AppModel, workflows: WorkflowRunner, mode: DockBadgePreference.Mode) -> Int {
        guard mode != .off else { return 0 }

        let tasks = Set(model.sessionList.map(\.id)).count { id in
            model.session(id)?.needsApproval == true || (mode == .needsYouAndUnread && model.isUnread(id))
        }
        return tasks + workflows.runs.count { $0.phase.needsUser }
    }
}
