import NativeCommands
import NativeSetup
import SwiftUI

extension View {
    /// Shows the agent picker as a sheet while `isPresented` (File ▸ New Session With…, ⌥⌘N).
    func agentPicker(isPresented: Binding<Bool>) -> some View {
        modifier(AgentPickerPresenter(isPresented: isPresented))
    }
}

/// A sheet, like Search and Run Workflow: a window of its own, so it takes the keyboard however it
/// was opened (an overlay loses it to the composer's text view), and closing it gives the keyboard
/// back to whatever had it. It reads whether it shows in a body of its own, so opening it doesn't
/// redraw the window's root view.
private struct AgentPickerPresenter: ViewModifier {
    @Binding var isPresented: Bool

    /// What the picker closed for, done once it's gone, since a sheet or alert (Add Agent, a
    /// sign-in) can't open while it's still on screen.
    @State private var next: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: $isPresented,
            onDismiss: {
                let action = next
                next = nil
                action?()
            }
        ) {
            AgentPickerSheet { action in
                next = action
                isPresented = false
            }
        }
    }
}

/// The picker wired to the app model.
private struct AgentPickerSheet: View {
    /// Closes the picker, then does `action`, if any.
    let close: (_ then: (@MainActor () -> Void)?) -> Void

    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings

    /// What Add Agent offers, less any agent already listed with its state (one found missing at
    /// launch keeps its row until the check for agents drops it).
    private var missingAgents: [String] {
        let listed = Set(model.agents.map(\.agent.id))
        return model.agentsToAdd.filter { !listed.contains($0.id) }.map(\.displayName)
    }

    var body: some View {
        AgentPickerPanel(
            options: model.agentPickerOptions(),
            projectName: model.currentProject?.name,
            missingAgents: missingAgents,
            defaultShortcut: CommandRegistry.shared.shortcut(for: .sessionNew)?.displayString,
            onChoose: { option in
                close { Task { await model.chooseAgentForNewSession(option.id) } }
            },
            onRemedy: { option in await model.restart(option.id) },
            onAddAgent: { close { model.isAddingAgent = true } },
            onDismiss: { close(nil) }
        ) {
            if let problem = model.agentPickerBlocker {
                NoticeBanner(tone: .warning, title: problem.title, detail: problem.recovery) {
                    Button("Retry") { Task { await model.retry(problem) } }
                        .buttonStyle(.ds(.secondary))
                        .disabled(model.isRetrying(problem))
                }
                .padding([.horizontal, .top], DS.Space.md)
            } else if let failure = model.agentStartupFailure {
                NoticeBanner(tone: .warning, title: failure.title, detail: failure.message) {
                    Button("Agents Settings") { close { settings.open(.agents) } }
                        .buttonStyle(.ds(.secondary))
                }
                .padding([.horizontal, .top], DS.Space.md)
            }
        }
        // Going somewhere else while it's open (⌘N, ⌘1) is a choice made another way.
        .onChange(of: model.selection) { close(nil) }
    }
}
