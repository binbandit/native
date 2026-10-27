import ACP
import SwiftUI

struct ChangeAgentSheet: View {
    @Bindable var change: ChangeAgentModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("Change Agent")
                .font(.dsHeadline)
            Text("Keep this task's worktree and branch. Its earlier transcript stays under Earlier Conversation.")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = change.blockedReason {
                Text(reason)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            } else if change.choices.isEmpty {
                Text(
                    "No other agent is ready. Install or sign in to another agent in Settings > Agents, then try again."
                )
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
            } else {
                Picker("Continue with", selection: $change.agentID) {
                    ForEach(change.choices, id: \.agent.id) { runtime in
                        Text(runtime.agent.displayName).tag(Optional(runtime.agent.id))
                    }
                }
                .disabled(change.candidate != nil || change.isWorking)

                if change.candidate != nil {
                    if !change.modelChoices.isEmpty {
                        Picker("Model", selection: $change.modelValue) {
                            ForEach(change.modelChoices, id: \.value) { option in
                                Text(option.name).tag(option.value)
                            }
                        }
                        .disabled(change.isWorking)
                    } else {
                        Text("This agent uses its default model and does not offer a model picker.")
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextSecondary)
                    }
                }

                if change.isLoadingContext {
                    LoadingStateView("Preparing handoff…")
                        .frame(height: DS.AgentChange.editorHeight)
                } else {
                    Text("Review the first message")
                        .font(.dsCaptionMedium)
                        .foregroundStyle(.dsTextSecondary)
                    TextEditor(text: $change.handoff)
                        .font(.dsBody)
                        .scrollContentBackground(.hidden)
                        .padding(DS.Space.md)
                        .frame(height: DS.AgentChange.editorHeight)
                        .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(.dsBorder))
                        .accessibilityLabel("Handoff")
                        .disabled(change.isWorking)
                    Text(
                        "Native assembled excerpts locally. Edit them before sending. Goal text is included; goal automation stays with the earlier conversation."
                    )
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error = change.error {
                Text(error)
                    .font(.dsBody)
                    .foregroundStyle(.dsDanger)
                    .textSelection(.enabled)
            }
            if change.isWorking {
                LoadingStateView(change.candidate == nil ? "Starting agent…" : "Sending handoff…")
                    .frame(height: DS.AgentChange.progressHeight)
            }
            HStack(spacing: DS.Space.md) {
                Spacer(minLength: 0)
                Button("Cancel") { change.cancel() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .keyboardShortcut(.cancelAction)
                    .disabled(change.isWorking && change.candidate != nil)
                Button(change.candidate == nil ? "Choose Model" : "Change Agent and Send") {
                    Task {
                        if change.candidate == nil { await change.prepare() } else { await change.send() }
                    }
                }
                .buttonStyle(.ds(.primary, size: .medium))
                .disabled(
                    change.isWorking || change.isLoadingContext || change.blockedReason != nil
                        || change.agentID == nil
                        || change.handoff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DS.Space.xxl)
        .frame(idealWidth: DS.AgentChange.sheetWidth, maxWidth: DS.AgentChange.sheetWidth)
        .background(.dsBackground)
        .interactiveDismissDisabled()
        .task { await change.loadContext() }
    }
}

extension View {
    func changeAgentPresentation() -> some View {
        modifier(ChangeAgentPresentation())
    }
}

private struct ChangeAgentPresentation: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { app.changingAgent != nil },
                set: { if !$0 { app.changingAgent?.cancel() } }
            )
        ) {
            if let change = app.changingAgent { ChangeAgentSheet(change: change) }
        }
        #if DEBUG
        .overlay {
            if let state = ComposerAgentModelPreview.requested {
                ComposerAgentModelPreview(stateID: state)
            }
        }
        #endif
    }
}

#if DEBUG
#Preview("Change Agent - Review") {
    let app = ChangeAgentPreviewFixtures.app()
    DSPreviewPair {
        if let source = ChangeAgentPreviewFixtures.source(in: app) {
            ChangeAgentSheet(change: .preview(in: app, source: source))
        }
    }
}

#Preview("Change Agent - Start failure") {
    let app = ChangeAgentPreviewFixtures.app()
    DSPreviewPair {
        if let source = ChangeAgentPreviewFixtures.source(in: app) {
            ChangeAgentSheet(
                change: .preview(
                    in: app, source: source, error: "The agent stopped. Cancel and restart it in Settings > Agents."))
        }
    }
}
#Preview("Change Agent - Running turn") {
    let app = ChangeAgentPreviewFixtures.app()
    DSPreviewPair {
        if let source = ChangeAgentPreviewFixtures.source(in: app) {
            let change = ChangeAgentModel.preview(in: app, source: source)
            ChangeAgentSheet(change: change)
                .onAppear { source.phase = .prompting }
        }
    }
}
#endif
