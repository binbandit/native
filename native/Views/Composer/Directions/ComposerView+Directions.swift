#if DEBUG
import ACP
import NativeCommands
import SwiftUI
import UniformTypeIdentifiers

// The composer directions (`-composerDesign a|b|c|d`) drive the session through the same state and
// actions as today's composer; this hands them the pieces.
extension ComposerView {
    /// Whether the slash and file lists float above the composer, as today; direction B lists them
    /// inside it.
    var floatsSuggestions: Bool {
        ComposerDirection.launchChoice != .command
    }

    /// Direction B's setting commands, for the `/` list.
    var directionCommands: [ComposerSlashCommand] {
        guard ComposerDirection.launchChoice == .command else { return [] }
        return CommandLineSettingQuery.commands(
            settings: ComposerSettings(session.configOptions), mode: TaskModeControl(session: session),
            resumedAutonomy: autonomyBeforePlan)
    }

    @ViewBuilder
    func directionSurface(
        _ direction: ComposerDirection, settings: ComposerSettings, suggestions: ComposerSuggestions?
    ) -> some View {
        let parts = directionParts(settings, suggestions: suggestions)
        Group {
            switch direction {
            case .quiet:
                QuietComposer(
                    parts: parts, editor: { directionEditor(suggestions, placeholder: $0) },
                    sections: { directionSections(suggestions) }, files: { directionFiles })
            case .command:
                CommandLineComposer(
                    parts: parts, editor: { directionEditor(suggestions, placeholder: $0) },
                    sections: { directionSections(suggestions) }, files: { directionFiles })
            case .message:
                MessageCardComposer(
                    parts: parts, editor: { directionEditor(suggestions, placeholder: $0) },
                    sections: { directionSections(suggestions) }, files: { directionFiles })
            case .moment:
                MomentComposer(
                    parts: parts, editor: { directionEditor(suggestions, placeholder: $0) },
                    sections: { directionSections(suggestions) }, files: { directionFiles })
            }
        }
        .dropDestination(for: ComposerDropItem.self) { items, _ in
            attach(items)
            return !items.isEmpty
        } isTargeted: {
            isDropTargeted = $0
        }
        // ⌘U and File ▸ Attach Files… open the picker here, as the "+" chip does today.
        .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) {
            result in
            if case .success(let urls) = result, !urls.isEmpty {
                attach(urls)
            }
        }
        .fileDialogDefaultDirectory(session.cwd)
        .background {
            // Stop's shortcut, as today's composer has it.
            if session.canCancel {
                Button("Stop", action: stop)
                    .keyboardShortcut(CommandRegistry.shared.keyboardShortcut(for: .sessionStop))
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            if let url = ComposerDirection.launchAttachment, !Self.didAttachLaunchFile {
                Self.didAttachLaunchFile = true
                attach([url])
            }
        }
        .animation(.dsStandard, value: session.queuedPrompts)
        .animation(.dsStandard, value: session.permissionRequests.count)
        .animation(.dsStandard, value: session.canCancel)
    }

    /// The launch's file goes on the first composer that shows, once.
    private static var didAttachLaunchFile = false

    private func directionParts(
        _ settings: ComposerSettings, suggestions: ComposerSuggestions?
    )
        -> ComposerDirectionParts
    {
        ComposerDirectionParts(
            session: session, settings: settings, mode: TaskModeControl(session: session), suggestions: suggestions,
            highlighted: $highlighted, changedFiles: mentionSource?.changed ?? [], followUp: followUp,
            followUpHint: followUpHint, hasContent: hasContent, isWorking: isWorking, canEdit: canEdit,
            isFocused: isFocused, resumedAutonomy: autonomyBeforePlan,
            sendBlockedReason: session.sendBlockedReason ?? attachmentsBlockedReason,
            isDropTargeted: isDropTargeted || drops?.isTargeted == true, isModelPickerOpen: $isModelPickerOpen,
            isPickingFiles: $isPickingFiles,
            submit: directionSubmit, stop: stop, set: { set($0, to: $1) }, sendNow: { sendNow($0) }, edit: edit,
            remove: remove, chooseCommand: insert, chooseFile: insert,
            write: { text in
                session.draft = text
                selection = TextSelection(insertionPoint: session.draft.endIndex)
                isFocused = true
            },
            applyChoice: applyChoice)
    }

    func directionEditor(_ suggestions: ComposerSuggestions?, placeholder: String?) -> some View {
        ComposerEditor(
            text: $session.draft, selection: $selection, placeholder: placeholder ?? self.placeholder,
            isFocused: $isFocused, hidesCaret: selectedAttachmentIndex != nil
        ) { press in
            directionKey(press, suggestions: suggestions)
        }
        .disabled(!canEdit)
        .onAttachmentPaste(isEnabled: isFocused && canEdit, perform: attach)
    }

    /// The sections every direction keeps from today: the goal, the agent's question, its plan, and
    /// the next steps after a turn. Listed suggestions take their place, as today.
    @ViewBuilder
    func directionSections(_ suggestions: ComposerSuggestions?) -> some View {
        if suggestions == nil {
            let plan = PlanProgress(entries: session.plan)
            SessionGoalBar(session: session)
            if let question = session.pendingQuestion {
                AgentQuestionDock(session: session, question: question)
                    .id(question.id)
            }
            if plan.isActive {
                ComposerPlanSection(plan: plan, isWorking: isWorking, isExpanded: $isPlanExpanded)
            }
            if showsNextSteps {
                NextStepsSection(steps: nextSteps)
            }
        }
    }

    @ViewBuilder
    var directionFiles: some View {
        if !session.attachments.isEmpty || !pendingAttachments.isEmpty {
            ComposerAttachmentsSection(
                attachments: session.attachments,
                pending: pendingAttachments,
                missing: missingAttachments,
                selected: selectedAttachment,
                capabilities: session.promptCapabilities,
                agentName: session.agentName,
                onRemove: removeAttachment
            )
        }
    }

    /// Sends the draft; in direction D, a message written while an approval waits rejects the request
    /// first and goes into the turn as what to do instead.
    private func directionSubmit(_ behavior: FollowUpBehavior) {
        guard ComposerDirection.answersApprovals, hasContent, let call = session.permissionRequests.first,
            let reject = call.permission?.options.first(where: { $0.kind == .rejectOnce })
        else {
            return submit(behavior)
        }
        Task {
            await session.choose(reject, forToolCall: call.id)
            submit(.steer)
        }
    }

    /// Direction B's setting list takes the arrows, Return, Tab and Escape while it shows, and in D,
    /// Return answers a waiting approval with the draft; everything else is today's keys.
    private func directionKey(_ press: KeyPress, suggestions: ComposerSuggestions?) -> KeyPress.Result {
        if ComposerDirection.answersApprovals, press.key == .return, press.modifiers.isEmpty, hasContent,
            !session.permissionRequests.isEmpty, suggestions == nil
        {
            directionSubmit(.steer)
            return .handled
        }
        guard ComposerDirection.launchChoice == .command, let query = CommandLineSettingQuery(draft: session.draft)
        else {
            return handleKey(press, suggestions: suggestions)
        }
        let choices = query.choices(
            settings: ComposerSettings(session.configOptions), mode: TaskModeControl(session: session),
            resumedAutonomy: autonomyBeforePlan)
        guard !choices.isEmpty, press.modifiers.isEmpty || press.key == .escape else {
            return handleKey(press, suggestions: suggestions)
        }
        switch press.key {
        case .upArrow:
            highlighted = max(highlighted - 1, 0)
        case .downArrow:
            highlighted = min(highlighted + 1, choices.count - 1)
        case .return, .tab:
            session.draft = ""
            applyChoice(choices[min(highlighted, choices.count - 1)])
        case .escape:
            session.draft = ""
        default:
            return handleKey(press, suggestions: suggestions)
        }
        return .handled
    }

    private func applyChoice(_ choice: CommandLineChoice) {
        switch choice.action {
        case .setting(let setting, let value):
            set(setting, to: value)
        case .mode(let id):
            TaskModeControl(session: session).select(id)
        }
        feedback = ComposerFeedback(tone: .done, message: "Set to \(choice.name)")
        isFocused = true
    }
}
#endif
