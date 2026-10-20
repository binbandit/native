#if NATIVE_PREVIEWS_WIP
import Foundation
import NativeAutomation

extension AutomationCenter {
    /// A center that keeps nothing and runs nothing: runs and automations live in memory, goals read
    /// from a file that doesn't exist (and are never set here, so nothing is written), and no host is
    /// connected, so no step or automation can start an agent.
    static func preview() -> AutomationCenter {
        AutomationCenter(
            goalStore: GoalStore(
                url: FileManager.default.temporaryDirectory.appending(path: "native-preview-goals-unused.json")),
            workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
    }
}
#endif
