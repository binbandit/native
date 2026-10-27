import ACP
import Modes
import SwiftUI

extension ComposerView {
    func inputSection(suggestions: ComposerSuggestions?) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ComposerEditor(
                text: Binding(get: { draftText }, set: { draftText = $0 }), selection: $selection,
                placeholder: placeholder, isFocused: $isFocused,
                hidesCaret: selectedAttachmentIndex != nil,
                insets: composerNext ? DS.ComposerSettings.textInsets : DS.Composer.textInsets,
                referencesEnabled: composerNext, referenceCounts: fileReferenceCounts
            ) { press in
                handleKey(press, suggestions: suggestions)
            }
            .disabled(!canEdit)
            .onAttachmentPaste(isEnabled: isFocused && canEdit, perform: attach)
            // Send and Stop keep their places, so neither moves nor reflows the text: Send alone while
            // idle (once there's a draft); while the agent works, Stop, with a slot
            // beside it where Send appears to queue or steer what's typed, by pointer or touch too.
            HStack(spacing: composerNext ? DS.Space.xs : DS.Space.sm) {
                if composerNext {
                    ContextIndicator(
                        session: session, style: .field, revealsAt: ComposerNextField.contextRevealedAt,
                        breakdown: $isContextUseOpen)
                    ComposerSettingsControl(
                        session: session, settings: ComposerSettings(session.configOptions),
                        mode: TaskModeControl(session: session, modes: taskModes),
                        isPresented: $isModelPickerOpen, resumedAutonomy: autonomyBeforePlan,
                        highlightsCurrent: settingsOpenedByCommand)
                    AttachButton(isPickingFiles: $isPickingFiles, onPick: attach, isField: true)
                        .fileDialogDefaultDirectory(session.cwd)
                }
                if session.canCancel {
                    actionSlot { if hasContent { sendButton } }
                    actionSlot {
                        // Escape stops from the editor through its keys (`ComposerKeyMap`), which
                        // see it first; the button's own Escape covers focus anywhere else.
                        ComposerStopButton(
                            isEscapeEnabled: overlayDismissal == nil && !isFocused && suggestions == nil
                                && selectedAttachmentIndex == nil && !windowClaimsCancelKeys,
                            action: stop
                        )
                    }
                } else if !composerNext || hasContent {
                    actionSlot { if hasContent { sendButton } }
                }
            }
            .padding(composerNext ? DS.ComposerSettings.trailingInset : DS.Space.md)
            .focusedSceneValue(\.contextUsePopover, composerNext ? $isContextUseOpen : nil)
            .onChange(of: isModelPickerOpen) { _, open in
                if !open {
                    settingsOpenedByCommand = false
                    takeFocusIfWanted()
                }
            }
        }
        .frame(minHeight: composerNext ? DS.ComposerSettings.inputHeight : DS.Size.composerInputMinHeight)
        .background {
            // Stop's shortcut (⌘. unless remapped) stops the turn too; a button takes one shortcut,
            // so this one is invisible.
            if session.canCancel {
                Button("Stop", action: stop)
                    .keyboardShortcut(CommandRegistry.shared.keyboardShortcut(for: .sessionStop))
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(.dsQuick, value: hasContent)
        .animation(.dsQuick, value: session.canCancel)
    }

    /// Disabled in place when something blocks sending, saying why.
    var sendButton: some View {
        let behavior = session.supportsSteering ? followUp : .queue
        // An item can leave the queue while its editor stays open; submission then sends a new message.
        let isEditingQueued =
            session.queuedPrompts.contains { $0.id == session.editingQueuedPrompt }
            && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ComposerSendButton(disabledReason: session.sendBlockedReason ?? attachmentsBlockedReason) {
            submit(followUp)
        }
        .accessibilityLabel(
            isEditingQueued ? "Save Queued Message" : isWorking ? "\(behavior.title) Message" : "Send Message"
        )
        .help(
            isEditingQueued
                ? "Save the edit, keeping its place in the queue."
                : isWorking ? "\(behavior.title): \(behavior.explanation)" : "Send (↩)")
    }

}

/// Fine print's field.
enum ComposerNextField {
    /// The context ring joins the field's controls from this full; the task's tools always show it.
    static let contextRevealedAt = 0.7

    /// The idle field's invitation, naming the mode when it isn't Build.
    static func placeholder(mode: Mode, agent: String) -> String {
        switch mode.id {
        case .build: "Message \(agent)"
        case .plan: "Plan with \(agent)"
        case .ask: "Ask \(agent)"
        case .debug: "Debug with \(agent)"
        case .review: "Review with \(agent)"
        default: "Message \(agent) in \(mode.name)"
        }
    }
}
