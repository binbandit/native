import ACP
import Modes
import NativeAutomation
import SwiftUI

/// The prompt composer: one surface pinned under the transcript that stacks queued
/// follow-ups, the agent's plan, the draft and a row of session controls, with slash commands and
/// `@` file mentions floating above it. Its keys follow docs/keyboard.md.
struct ComposerView: View {
    @Bindable var session: SessionModel
    /// The same draft component, laid out as a page before the task starts.
    var page: ComposerPageConfiguration? = nil
    /// Previews supply an in-memory mode library.
    var taskModes: TaskModes = .shared
    @Experiment(.composerNext) var composerNext

    @AppStorage(FollowUpBehavior.storageKey) var followUp = FollowUpBehavior.defaultValue
    @Environment(\.undoManager) var undoManager
    @Environment(\.composerNextSteps) var nextSteps
    @Environment(\.composerOverlayDismissal) var overlayDismissal
    @Environment(\.transcriptColumnMaxWidth) var columnWidth
    @Environment(AutomationCenter.self) var automation
    @Environment(AppModel.self) var app
    @Environment(\.composerFileReferenceCounts) var fileReferenceCounts
    /// Drops on the transcript around the composer, when its host takes them.
    @Environment(ComposerDropInbox.self) var drops: ComposerDropInbox?
    @FocusState var isFocused: Bool
    @State var selection: TextSelection?
    /// The highlighted row of the suggestion list.
    @State var highlighted = 0
    /// Escape closes the suggestion list until the draft stops asking for one.
    @State var suggestionsDismissed = false
    /// The draft as an agent's command left it when picked from the list, so it goes to the agent
    /// even where Native has a command of the same name.
    @State var agentCommandDraft: String?
    @State var mentionSource: FileMentionSource?
    @State var isPlanExpanded = false
    @State var isModelPickerOpen = false
    /// Fine print's Task Settings was opened by Choose Model (⇧⌘E), so it highlights the current model.
    @State var settingsOpenedByCommand = false
    /// Fine print's context breakdown, which View ▸ Show Context Use opens below 70% too.
    @State var isContextUseOpen = false
    @State var isDropTargeted = false
    /// The file picker, from the "+" chip or File ▸ Attach Files….
    @State var isPickingFiles = false
    /// The autonomy level Plan Mode returns to, remembered from before it started.
    @State var autonomyBeforePlan: String?
    /// What the last action did, shown for a moment just above the composer.
    @State var feedback: ComposerFeedback?
    /// Files still being read, as chips in their places; sending waits for them.
    @State var pendingAttachments: [ComposerPendingAttachment] = []
    /// Attached files found gone at the last try to send, marked on their chips.
    @State var missingAttachments: Set<PromptAttachment.ID> = []
    /// The chip ← selected from the start of the text (`DraftAttachmentKeys`); nil while the keys go
    /// to the text.
    @State var selectedAttachment: PromptAttachment.ID?

    var draftText: String {
        get { composerNext ? session.composerMessage : session.draft }
        nonmutating set {
            if composerNext { session.composerMessage = newValue } else { session.draft = newValue }
        }
    }

    /// Fine print: an approval or a question takes the composer's place until it's answered; the
    /// draft waits underneath.
    var asksInPlace: Bool {
        composerNext && page == nil && (!session.permissionRequests.isEmpty || session.pendingQuestion != nil)
    }

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

    /// The `@` mention at the cursor, if one is being typed. Never in code, where `@` is the code's
    /// own (a decorator, an attribute).
    var mentionQuery: FileMentionQuery? {
        guard let range = selectedRange, !PromptCode.isInCode(range.upperBound, in: draftText) else { return nil }
        return FileMentionQuery(draft: draftText, cursor: range.upperBound)
    }

    /// Commands while the draft is a bare "/command"; files while an `@` mention is typed.
    var suggestions: ComposerSuggestions? {
        guard !suggestionsDismissed else { return nil }
        if let query = SlashCommandQuery(draft: draftText) {
            let commands = query.matches(
                in: nativeCommands + session.availableCommands.map(ComposerSlashCommand.init))
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
        var commands: [ComposerSlashCommand] = []
        if page == nil, session.origin == .user, !session.isSubagent {
            commands.append(
                ComposerSlashCommand(
                    native: ClearConversationCommand.name, description: ClearConversationCommand.summary))
        }
        if automation.goal(for: session) != nil {
            commands.append(ComposerSlashCommand(native: "goal", description: GoalCommand.usage))
        }
        return commands
    }

    var body: some View {
        let settings = ComposerSettings(session.configOptions)
        let suggestions = asksInPlace ? nil : suggestions
        Group {
            if page != nil {
                pageSurface(suggestions: suggestions)
            } else if composerNext, let call = session.permissionRequests.first {
                ApprovalSurface {
                    SessionApprovalView(session: session, call: call)
                }
            } else if composerNext, let question = session.pendingQuestion {
                ApprovalSurface {
                    SessionQuestionView(session: session, question: question)
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    surface(settings, suggestions: suggestions)
                    if composerNext { settingsNote(settings) }
                }
            }
        }
        .overlay(alignment: .top) {
            // Float above the composer instead of growing it, so the transcript doesn't move:
            // a zero-height frame on the top edge, with the list or toast hanging up out of it.
            Group {
                if let suggestions {
                    ComposerSuggestionsPanel(
                        suggestions: suggestions,
                        highlighted: $highlighted,
                        changedFiles: mentionSource?.changed ?? [],
                        referenceCounts: fileReferenceCounts,
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
        .frame(
            maxWidth: page != nil
                ? DS.ComposeTask.width
                : composerNext ? max(columnWidth, DS.ComposerSettings.width) : columnWidth
        )
        .padding(.horizontal, page == nil ? DS.Space.xxl : 0)
        .padding(.top, page == nil ? DS.Space.md : 0)
        .padding(.bottom, page == nil ? DS.Space.xl : 0)
        .frame(maxWidth: .infinity)
        // Only a brand-new session takes focus on its own (⌘N, then type). Others wait for ⌘L or a
        // click, so arrowing through the sidebar doesn't hand Return to a composer.
        .onAppear {
            app.restoreAgentModelChoice(for: session)
            if session.isTranscriptEmpty, session.phase != .loading {
                isFocused = true
            }
            takeFocusIfWanted()
        }
        .onChange(of: session.draft) { draftChanged() }
        .onChange(of: pendingAttachments.isEmpty) { _, empty in page?.attachmentsPending(!empty) }
        // A click in the text, typing, or the editor losing focus hands the keys back to the text.
        .onChange(of: selection) { selectedAttachment = nil }
        .onChange(of: isFocused) { _, focused in
            if !focused { selectedAttachment = nil }
        }
        // Undo by any route (⌘Z, Edit ▸ Undo, the toast's button) takes back what the toast offered
        // to, so the toast goes with it.
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { note in
            if let undoManager, note.object as? UndoManager === undoManager, feedback?.canUndo == true {
                feedback = nil
            }
        }
        .onChange(of: mentionQuery != nil) { _, isMentioning in
            guard isMentioning, page?.allowsFileMentions != false else { return }
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
            if let page {
                page.openSettings()
            } else {
                settingsOpenedByCommand = true
                isModelPickerOpen = true
            }
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
        let plan = PlanProgress(entries: session.plan)
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
                        editing: session.editingQueuedPrompt,
                        sendNow: session.sendNowRoute,
                        agentName: session.agentName,
                        onSendNow: { sendNow($0) },
                        onMove: { id, direction in session.moveQueued(id, direction) },
                        onDrop: { id, target in session.moveQueued(id, before: target) },
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
                    selected: selectedAttachment,
                    capabilities: session.promptCapabilities,
                    agentName: session.agentName,
                    onRemove: removeAttachment
                )
            }
            VStack(spacing: 0) {
                if composerNext, let change = session.modelChange {
                    ComposerAgentReceiptSection(change: change)
                }
                if composerNext, !session.composerQuotes.isEmpty {
                    ComposerQuotesSection(quotes: session.composerQuotes) {
                        session.removeQuote(at: $0, undoManager: undoManager)
                    }
                    SeparatorLine()
                }
                // Keep the editor mounted when a turn changes the footer, preserving focus and selection.
                inputSection(suggestions: suggestions)
                if !composerNext {
                    Rectangle().fill(.dsBorder).frame(height: DS.Composer.separatorWidth)
                    currentControls(settings)
                }
            }
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

    /// What the controls row's hint says: the keys in a code block, the keys for the queued message
    /// open in the editor, or nothing during ordinary messaging.
    var followUpHint: FollowUpHint? {
        if isCaretInCodeBlock {
            return codeBlockHint
        }
        if session.editingQueuedPrompt != nil {
            return .editingQueued(
                sendNow: session.sendNowRoute.map { QueuedSendNow(route: $0, agentName: session.agentName) })
        }
        return nil
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

    /// Invites a message, or explains what the session is waiting for.
    var placeholder: String {
        if composerNext, session.phase == .idle {
            return ComposerNextField.placeholder(
                mode: TaskModeControl(session: session, modes: taskModes).current, agent: session.agentName)
        }
        return ComposerPlaceholder(
            phase: session.phase,
            agentName: session.agentName,
            hasQuestion: session.pendingQuestion != nil,
            needsApproval: session.needsApproval,
            isStopping: session.isStopping,
            isNewSession: session.isTranscriptEmpty,
            showsFocusHint: canEdit && !isFocused && ComposerPlatform.showsKeyboardHints
        ).text
    }

    /// Takes focus when the app asks (⌘L, a click on the session in the sidebar), then clears the ask.
    func takeFocusIfWanted() {
        guard session.wantsComposerFocus, !asksInPlace, !isModelPickerOpen else { return }
        isFocused = true
        session.wantsComposerFocus = false
    }
}

#if DEBUG
#Preview("Composer - Fine print approval") {
    DSPreviewPair { ApprovalPreviewFixtures.composer().frame(width: 850) }
}

#Preview("Composer - Fine print question") {
    DSPreviewPair { AskPreviewFixtures.questionComposer().frame(width: 850) }
}
#endif
