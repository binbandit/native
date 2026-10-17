import Foundation
import NativeAutomation

/// Connects the Git feature to Automations, which don't know about each other: pushes Native makes
/// feed the "branch pushed" trigger.
enum GitAutomationWiring {
    static func connect(_ git: GitStore, to automations: AutomationEngine) {
        git.onBranchPushed = { project, branch in
            automations.noteBranchPushed(project: project, branch: branch)
        }
    }
}
