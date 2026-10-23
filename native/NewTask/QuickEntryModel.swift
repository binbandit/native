import ACP
import Experiments
import Foundation
import Observation

/// A draft has no agent session or worktree until Start or Expand is chosen.
@Observable
final class QuickEntryModel {
    enum Picker: Equatable {
        case agent, device, project
    }

    struct Context: Equatable {
        let source: String
        let text: String
    }

    var isEnabled: Bool { ExperimentStore.shared.value(of: .composeTask) }
    var isPresented = false
    var isChoosingFolder = false
    /// Explicit navigation, so RootView can reveal a task even while Settings is showing.
    var taskOpenRequests = 0
    var draft = ""
    var context: Context?
    var project: Project.ID?
    var agent: AgentDefinition.ID?
    var device = SessionDevice.thisMac
    var picker: Picker?
    var failure: String?
    var lastStartedTask: StartingTask?
    #if DEBUG
    var previewDeviceOptions: [SessionDeviceOption]?
    #endif

    var message: String {
        guard let context else { return draft }
        let quote = context.text.components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n")
        return "\(draft)\n\nFrom \(context.source):\n\(quote)"
    }

    var hasMessage: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func dismiss() {
        picker = nil
        isPresented = false
    }

    func toggle(_ picker: Picker) {
        self.picker = self.picker == picker ? nil : picker
    }

    func clearAfterStarting() {
        dismiss()
        draft = ""
        context = nil
        failure = nil
    }
}
