import ACP
import SwiftUI

/// The second agent on the To line: its name and model on a token, like the first. Clicking it
/// offers another agent in its place, or taking it off.
struct ComposeSecondRecipient: View {
    let model: AppModel
    let compose: ComposeTaskModel
    let second: ComposeRecipient

    private var name: String { model.plugins.agent(second.agent)?.displayName ?? second.agent.rawValue }

    var body: some View {
        Menu {
            let others = model.composeSecondAgentChoices.filter { $0.agent.id != second.agent }
            if !others.isEmpty {
                Section("Send to instead") {
                    ForEach(others, id: \.agent.id) { runtime in
                        Button(runtime.agent.displayName) { model.addComposeAgent(runtime.agent.id) }
                    }
                }
            }
            Button("Remove \(name)", role: .destructive) { model.removeComposeAgent() }
        } label: {
            HStack(spacing: DS.Space.sm) {
                Text(name).foregroundStyle(.dsTextPrimary)
                if let modelName = second.modelName { Text(modelName).foregroundStyle(.dsTextSecondary) }
            }
            .font(.dsCallout)
            .padding(.horizontal, DS.ComposeTask.tokenPadding)
            .frame(height: DS.ComposeTask.tokenHeight)
            .background(.dsFill, in: .rect(cornerRadius: DS.Radius.control))
            .contentShape(.rect)
        }
        .menuStyle(.button).buttonStyle(ComposeAddressButtonStyle()).menuIndicator(.hidden).fixedSize()
        .dsHitTarget(DS.ComposeTask.rowHeight)
        .disabled(compose.isHeld || compose.stage != .writing)
        .help("Send to another agent instead, or remove \(name)")
        .accessibilityLabel("Second agent, \(name)")
        .accessibilityHint("Swap it for another agent or remove it")
    }
}
