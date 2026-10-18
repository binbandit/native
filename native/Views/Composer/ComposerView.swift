import ACP
import NativeAutomation
import SwiftUI

/// The prompt composer: one surface pinned under the transcript that stacks queued
/// follow-ups, the agent's plan, the draft and a row of session controls, with slash commands and
/// `@` file mentions floating above it. Its keys follow docs/keyboard.md.
struct ComposerView: View {
    @Bindable var session: SessionModel

    @AppStorage(FollowUpBehavior.storageKey) var followUp = FollowUpBehavior.defaultValue
    @Environment(\.undoManager) var undoManager
    @Environment(\.composerNextSteps) var nextSteps
    @Environment(\.transcriptColumnMaxWidth) var columnWidth
    @Environment(AutomationCenter.self) var automation
    /// Drops on the transcript around the composer, when its host takes them.
    @Environment(ComposerDropInbox.self) var drops: ComposerDropInbox?
    @FocusState var isFocused: Bool
    @State var selection: TextSelection?
    /// The highlighted row of the suggestion list.
    @State var highlighted = 0
    /// Escape closes the suggestion list until the draft stops asking for one.
    @State var suggestionsDismissed = false
    @State var mentionSource: FileMentionSource?
    @State var isPlanExpanded = false
    @State var isModelPickerOpen = false
    @State var isDropTargeted = false
    /// The file picker, from the "+" chip or File ▸ Attach Files….
    @State var isPickingFiles = false
    /// The queued follow-up open in the editor; Return saves it back to the queue.
    @State var editingQueued: SessionModel.QueuedPrompt.ID?
    /// The autonomy level Plan Mode returns to, remembered from before it started.
    @State var autonomyBeforePlan: String?
    /// What the last action did, shown for a moment just above the composer.
    @State var feedback: ComposerFeedback?
    /// Files still being read, as chips in their places; sending waits for them.
    @State var pendingAttachments: [ComposerPendingAttachment] = []
    /// Attached files found gone at the last try to send, marked on their chips.
    @State var missingAttachments: Set<PromptAttachment.ID> = []

    var canEdit: Bool {
        session.phase != .disconnected
    }

    var isWorking: Bool {
        session.phase == .prompting
    }

    /// Whether there's anything to send: text, or files on their own.
    var hasContent: Bool {
        !session.draft.isEmpty || !session.attachments.isEmpty
    }

    /// After a turn ends normally, until the user starts on the next message.
    var showsNextSteps: Bool {
        !nextSteps.isEmpty && session.phase == .idle && session.lastStopReason == .endTurn
            && !hasContent && session.queuedPrompts.isEmpty
    }

    /// The `@` mention at the cursor, if one is being typed.
    var mentionQuery: FileMentionQuery? {
        guard case .selection(let range)? = selection?.indices else { return nil }
        return FileMentionQuery(draft: session.draft, cursor: range.upperBound)
    }

    /// Commands while the draft is a bare "/command"; files while an `@` mention is typed.
    var suggestions: ComposerSuggestions? {
        guard !suggestionsDismissed else { return nil }
        if let query = SlashCommandQuery(draft: session.draft) {
            let commands = query.matches(
                in: nativeCommands + session.state.availableCommands.map(ComposerSlashCommand.init))
            return commands.isEmpty ? nil : .commands(commands)
        }
        if let query = mentionQuery, let mentionSource {
            let files = mentionSource.matches(for: query.text)
            return files.isEmpty ? nil : .files(files, query: query)
        }
        return nil
    }

    /// Commands Native handles itself, listed before the agent's.
    var nativeCommands: [ComposerSlashCommand] {
        guard automation.goal(for: session) != nil else { return [] }
        return [ComposerSlashCommand(name: "goal", description: GoalCommand.usage)]
    }

    var body: some View {
        let settings = ComposerSettings(session.state.configOptions)
        let suggestions = suggestions
        surface(settings, suggestions: suggestions)
            .overlay(alignment: .top) {
                // Float above the composer instead of growing it, so the transcript doesn't move:
                // a zero-height frame on the top edge, with the list or toast hanging up out of it.
                Group {
                    if let suggestions {
                        ComposerSuggestionsPanel(
                            suggestions: suggestions,
                            highlighted: $highlighted,
                            changedFiles: mentionSource?.changed ?? [],
                            onChooseCommand: insert,
                            onChooseFile: insert
                        )
                    } else {
                        toast
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.bottom, DS.Space.md)
                .frame(height: 0, alignment: .bottom)
                .animation(.dsQuick, value: feedback)
            }
            .frame(maxWidth: columnWidth)
            .padding(.horizontal, DS.Space.xxl)
            .padding(.top, DS.Space.md)
            .padding(.bottom, DS.Space.xl)
            .frame(maxWidth: .infinity)
            // Only a brand-new session takes focus on its own (⌘N, then type). Others wait for ⌘L or a
            // click, so arrowing through the sidebar doesn't hand Return to a composer.
            .onAppear {
                if session.state.items.isEmpty, session.phase != .loading {
                    isFocused = true
                }
                takeFocusIfWanted()
            }
            .onChange(of: session.draft) { draftChanged() }
            .onChange(of: mentionQuery != nil) { _, isMentioning in
                guard isMentioning else { return }
                let source = mentionSource ?? FileMentionSource(root: session.cwd)
                mentionSource = source
                Task { await source.loadIfNeeded() }
            }
            .task(id: feedback?.id) {
                guard let shown = feedback else { return }
                try? await Task.sleep(for: shown.duration)
                if feedback?.id == shown.id {
                    feedback = nil
                }
            }
            // ⌘L, mouse selection in the sidebar and ⇧⌘E reach the composer through the session.
            .onChange(of: session.wantsComposerFocus) { takeFocusIfWanted() }
            .onChange(of: session.isModelPickerRequested, initial: true) { _, isRequested in
                guard isRequested else { return }
                isModelPickerOpen = true
                session.isModelPickerRequested = false
            }
            .onChange(of: drops?.items.isEmpty == false) { _, hasDrops in
                guard hasDrops, let drops else { return }
                attach(drops.items)
                drops.items = []
            }
            .onChange(of: session.isAttachmentPickerRequested, initial: true) { _, isRequested in
                guard isRequested else { return }
                isPickingFiles = true
                session.isAttachmentPickerRequested = false
            }
            .onChange(of: settings.autonomy?.value, initial: true) { _, mode in
                if let mode, mode != ComposerSettings.planValue {
                    autonomyBeforePlan = mode
                }
            }
    }

    // MARK: - Layout

    func surface(_ settings: ComposerSettings, suggestions: ComposerSuggestions?) -> some View {
        let plan = PlanProgress(entries: session.state.plan)
        // Each child is a section of the surface, with a rule between it and the next.
        return ComposerSurface(isFloating: true, isDropTargeted: isDropTargeted || drops?.isTargeted == true) {
            // While suggestions are listed, they take the place of the sections above the draft.
            if suggestions == nil {
                SessionGoalBar(session: session)
                if let question = session.pendingQuestion {
                    AgentQuestionDock(session: session, question: question)
                        .id(question.id)
                }
                if !session.queuedPrompts.isEmpty {
                    QueuedPromptsSection(
                        prompts: session.queuedPrompts,
                        editing: editingQueued,
                        // After a cancelled turn the queue waits, idle, until one is sent by hand.
                        sendNow: isWorking
                            ? (session.supportsSteering ? .steer : nil) : session.phase == .idle ? .send : nil,
                        onSendNow: { id in Task { await session.steerQueued(id) } },
                        onEdit: edit,
                        onRemove: remove
                    )
                }
                if plan.isActive {
                    ComposerPlanSection(plan: plan, isWorking: isWorking, isExpanded: $isPlanExpanded)
                }
                if showsNextSteps {
                    NextStepsSection(steps: nextSteps)
                }
            }
            if !session.attachments.isEmpty || !pendingAttachments.isEmpty {
                ComposerAttachmentsSection(
                    attachments: session.attachments,
                    pending: pendingAttachments,
                    missing: missingAttachments,
                    capabilities: session.promptCapabilities,
                    agentName: session.agentName,
                    onRemove: removeAttachment
                )
            }
            inputSection(suggestions: suggestions)
            ComposerControlsRow(
                settings: settings,
                resumedAutonomy: autonomyBeforePlan,
                followUpHint: isWorking
                    ? FollowUpHint(
                        preferred: followUp, supportsSteering: session.supportsSteering, agentName: session.agentName)
                    : nil,
                isModelPickerOpen: $isModelPickerOpen,
                isPickingFiles: $isPickingFiles,
                onAttach: attach,
                onSet: set,
                onCycleEffort: { apply(settings.nextEffort) },
                onCycleAutonomy: { apply(settings.nextAutonomy) },
                onTogglePlan: { apply(settings.togglingPlan(resumedAutonomy: autonomyBeforePlan)) },
                extras: { SessionGoalControl(session: session) },
                context: { ContextIndicator(session: session, style: .labeled) }
            )
            // The file picker opens on the task's own folder.
            .fileDialogDefaultDirectory(session.cwd)
            .disabled(!canEdit)
        }
        .dropDestination(for: ComposerDropItem.self) { items, _ in
            attach(items)
            return !items.isEmpty
        } isTargeted: {
            isDropTargeted = $0
        }
        .animation(.dsStandard, value: plan.isActive)
        .animation(.dsStandard, value: session.attachments.isEmpty && pendingAttachments.isEmpty)
        .animation(.dsStandard, value: showsNextSteps)
        .animation(.dsStandard, value: session.queuedPrompts)
    }

    func inputSection(suggestions: ComposerSuggestions?) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ComposerEditor(text: $session.draft, selection: $selection, placeholder: placeholder, isFocused: $isFocused)
            { press in
                handleKey(press, suggestions: suggestions)
            }
            .disabled(!canEdit)
            .onAttachmentPaste(isEnabled: isFocused && canEdit, perform: attach)
            // Send and Stop keep their places, so neither moves nor reflows the text: Send alone while
            // idle (once there's a draft); while the agent works, Stop, with a slot
            // beside it where Send appears to queue or steer what's typed, by pointer or touch too.
            HStack(spacing: DS.Space.sm) {
                if session.canCancel {
                    actionSlot { if hasContent { sendButton } }
                    actionSlot {
                        ComposerStopButton(isEscapeEnabled: suggestions == nil) {
                            Task { await session.cancel() }
                        }
                    }
                } else {
                    actionSlot { if hasContent { sendButton } }
                }
            }
            .padding(DS.Space.md)
        }
        .frame(minHeight: DS.Size.composerInputMinHeight)
        .background {
            // Stop's shortcut (⌘. unless remapped) stops the turn too; a button takes one shortcut,
            // so this one is invisible.
            if session.canCancel {
                Button("Stop") { Task { await session.cancel() } }
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
        ComposerSendButton(disabledReason: session.sendBlockedReason ?? attachmentsBlockedReason) { submit(followUp) }
            .help(
                isWorking
                    ? FollowUpHint(
                        preferred: followUp, supportsSteering: session.supportsSteering, agentName: session.agentName
                    ).help : "Send (↩)")
    }

    func actionSlot(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack(content: content)
            .frame(width: DS.Size.composerAction, height: DS.Size.composerAction)
            .transition(.opacity)
    }

    /// What the last action did; else, while there's a draft, why it can't go out.
    @ViewBuilder
    var toast: some View {
        if let feedback {
            let onUndo: (() -> Void)? = feedback.canUndo ? { undo() } : nil
            ComposerToast(message: feedback.message, tone: feedback.tone, onUndo: onUndo)
                .id(feedback.id)
                .transition(.opacity)
        } else if let blocked = session.sendBlockedReason, hasContent {
            ComposerToast(message: blocked, tone: .problem)
                .transition(.opacity)
        }
    }

    /// Says what typing here will do: start work, queue or steer a follow-up, or nothing yet and why.
    var placeholder: String {
        ComposerPlaceholder(
            phase: session.phase,
            agentName: session.agentName,
            hasQuestion: session.pendingQuestion != nil,
            needsApproval: session.needsApproval,
            followUp: followUp,
            supportsSteering: session.supportsSteering,
            isNewSession: session.state.items.isEmpty,
            showsFocusHint: canEdit && !isFocused && ComposerPlatform.showsKeyboardHints
        ).text
    }

    /// Takes focus when the app asks (⌘L, a click on the session in the sidebar), then clears the ask.
    func takeFocusIfWanted() {
        guard session.wantsComposerFocus else { return }
        isFocused = true
        session.wantsComposerFocus = false
    }
}
