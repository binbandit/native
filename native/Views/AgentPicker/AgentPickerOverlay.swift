import NativeCommands
import SwiftUI

extension View {
    /// Puts the agent picker over this window's content while `isPresented` (File ▸ New Session
    /// With…, ⌥⌘N).
    func agentPicker(isPresented: Binding<Bool>) -> some View {
        modifier(AgentPickerPresenter(isPresented: isPresented))
    }
}

/// Reads whether the picker shows in a body of its own, so opening it doesn't redraw the window's
/// root view.
private struct AgentPickerPresenter: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                AgentPickerOverlay(isPresented: $isPresented)
                    .transition(.opacity.animation(.dsPopover))
            }
        }
    }
}

/// The picker wired to the app model, where the command palette floats; a click or tap outside
/// closes it.
private struct AgentPickerOverlay: View {
    @Binding var isPresented: Bool

    @Environment(AppModel.self) private var model

    /// What Add Agent offers, less any agent already listed with its state (one found missing at
    /// launch keeps its row until the check for agents drops it).
    private var missingAgents: [String] {
        let listed = Set(model.agents.map(\.agent.id))
        return model.agentsToAdd.filter { !listed.contains($0.id) }.map(\.displayName)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { isPresented = false }
                .accessibilityHidden(true)
            AgentPickerPanel(
                options: model.agentPickerOptions(),
                projectName: model.currentProject?.name,
                missingAgents: missingAgents,
                defaultShortcut: CommandRegistry.shared.shortcut(for: .sessionNew)?.displayString,
                onChoose: { option in Task { await model.chooseAgentForNewSession(option.id) } },
                onRemedy: { option in await model.restart(option.id) },
                onAddAgent: {
                    isPresented = false
                    model.isAddingAgent = true
                },
                onDismiss: { isPresented = false }
            ) {
                if let problem = model.agentPickerBlocker {
                    NoticeBanner(tone: .warning, title: problem.title, detail: problem.recovery) {
                        Button("Retry") { Task { await model.retry(problem) } }
                            .buttonStyle(.ds(.secondary))
                            .disabled(model.isRetrying(problem))
                    }
                    .padding([.horizontal, .top], DS.Space.md)
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, AgentPickerMetrics.topInset)
        }
        // Going somewhere else while it's open (⌘N, ⌘1) is a choice made another way.
        .onChange(of: model.selection) { isPresented = false }
    }
}
