import SwiftUI

/// The agent's popover offers the same model action as the Task menu and palette.
struct ChangeAgentControl: View {
    let session: SessionModel
    @Environment(AppModel.self) private var app
    @State private var isOpen = false

    var body: some View {
        if app.offersAgentChange {
            Button(session.agentName) { isOpen = true }
                .buttonStyle(.header)
                .accessibilityLabel("Agent: \(session.agentName)")
                .popover(isPresented: $isOpen) {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        Text(session.agentName).font(.dsHeadline)
                        if let reason = app.changeAgentBlock(for: session) {
                            Text(reason)
                                .font(.dsBody)
                                .foregroundStyle(.dsTextSecondary)
                        }
                        Button("Change Agent…") {
                            isOpen = false
                            app.requestAgentChange(session)
                        }
                        .buttonStyle(.ds(.secondary))
                        .disabled(app.changeAgentBlock(for: session) != nil)
                    }
                    .padding(DS.Space.xl)
                    .frame(width: DS.Size.popoverWidth)
                }
        }
    }
}

#if DEBUG
#Preview("Change Agent - Agent control") {
    let app = ChangeAgentPreviewFixtures.app()
    DSPreviewPair {
        if let source = ChangeAgentPreviewFixtures.source(in: app) {
            ChangeAgentControl(session: source)
        }
    }
    .environment(app)
}
#endif
