import SwiftUI

/// Where questions are written: the app's composer editor in its surface, Return to ask (queued
/// while an answer is coming), Shift-Return for a new line, and Stop while the agent answers.
struct PullRequestAskComposer: View {
    let conversation: PullRequestAskConversation

    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var conversation = conversation
        ComposerSurface {
            ComposerEditor(
                text: $conversation.draft, selection: $selection, placeholder: placeholder, isFocused: $isFocused,
                onKey: handle)
            ComposerControlsBar {
                Text(hint)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
            } trailing: {
                if conversation.isAnswering, conversation.draft.isEmpty {
                    ComposerStopButton(isEscapeEnabled: false) { Task { await conversation.stop() } }
                } else {
                    ComposerSendButton(disabledReason: disabledReason) { Task { await conversation.send() } }
                }
            }
        }
        .onChange(of: conversation.wantsComposerFocus, initial: true) { _, wants in
            guard wants else { return }
            isFocused = true
            conversation.wantsComposerFocus = false
        }
    }

    private var placeholder: String {
        conversation.session == nil ? "Ask about this pull request" : "Ask a follow-up"
    }

    private var hint: String {
        conversation.isAnswering ? "↩ Queue · Esc Stop" : "↩ Ask · ⇧↩ New line"
    }

    private var disabledReason: String? {
        if conversation.isPageUnavailable { return "The pull request hasn't loaded" }
        if conversation.isBusy { return "Getting the pull request ready" }
        if conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Type a question" }
        return nil
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .return where press.modifiers.isDisjoint(with: [.shift, .option]):
            guard conversation.canSend, !conversation.isPageUnavailable else { return .handled }
            Task { await conversation.send() }
            return .handled
        case .escape where conversation.isAnswering:
            Task { await conversation.stop() }
            return .handled
        default:
            return .ignored
        }
    }
}
