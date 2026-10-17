import Foundation

/// Why an automation's run couldn't start.
nonisolated enum AutomationError: LocalizedError {
    case workflowMissing
    case interruptedWhileStarting

    var errorDescription: String? {
        switch self {
        case .workflowMissing: "The workflow this automation runs isn't in the library anymore; the plugin that offered it may be off."
        case .interruptedWhileStarting: "Native quit before this run started."
        }
    }
}
