import ACP
import SwiftUI

/// The prompt composer, after the reference app's: one surface pinned under the transcript that stacks queued
/// follow-ups, the agent's plan, the draft and a row of session controls, with slash commands
/// floating above it. Its keys follow docs/keyboard.md.
struct ComposerView: View {
    @Bindable var session: SessionModel

    @AppStorage(FollowUpBehavior.storageKey) private var followUp = FollowUpBehavior.defaultValue
    @Environment(\.undoManager) private var undoManager
    @Environment(\.composerNextSteps) private var nextSteps
    @FocusState private var isFocused: Bool
    /// The highlighted row of the slash-command list.
    @State private var highlighted = 0
    /// Escape closes the command list until the draft stops being a bare "/command".
    @State private var commandsDismissed = false
    @State private var isPlanExpanded = false
    @State private var isModelPickerOpen = false
    @State private var isDropTargeted = false
    /// The queued follow-up open in the editor; Return saves it back to the queue.
    @State private var editingQueued: SessionModel.QueuedPrompt.ID?
    /// The autonomy level Plan Mode returns to, remembered from before it started.
    @State private var autonomyBeforePlan: String?
    /// What the last action did, shown for a moment just above the composer.
    @State private var feedback: ComposerFeedback?

    private var canEdit: Bool {
        session.phase != .loading && session.phase != .disconnected
    }

    private var isWorking: Bool {
        session.phase == .prompting
    }

    private var blocker: SendBlocker? {
        SendBlocker(phase: session.phase, acceptsPrompts: session.acceptsPrompts, agentName: session.agentName)
    }

    /// After a turn ends normally, until the user starts on the next message.
    private var showsNextSteps: Bool {
        !nextSteps.isEmpty && session.phase == .idle && session.lastStopReason == .endTurn
            && session.draft.isEmpty && session.queuedPrompts.isEmpty
    }

    /// The slash commands to list: only while the draft is a bare "/command" being typed.
    private var commandMatches: [AvailableCommand] {
        guard !commandsDismissed, let query = SlashCommandQuery(draft: session.draft) else { return [] }
        return query.matches(in: session.state.availableCommands)
    }

    var body: some View {
        let settings = ComposerSettings(session.state.configOptions)
        let commands = commandMatches
        surface(settings, commands: commands)
            .overlay(alignment: .top) {
                // Float above the composer instead of growing it, so the transcript doesn't move:
                // a zero-height frame on the top edge, with the list or toast hanging up out of it.
                Group {
                    if !commands.isEmpty {
                        SlashCommandList(commands: commands, highlighted: $highlighted, onChoose: insert)
                    } else {
                        toast
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.bottom, DS.Space.md)
                .frame(height: 0, alignment: .bottom)
                .animation(.dsQuick, value: feedback)
            }
            .frame(maxWidth: transcriptColumnWidth)
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
            .onChange(of: settings.autonomy?.value, initial: true) { _, mode in
                if let mode, mode != ComposerSettings.planValue {
                    autonomyBeforePlan = mode
                }
            }
    }

    // MARK: - Layout

    private func surface(_ settings: ComposerSettings, commands: [AvailableCommand]) -> some View {
        let plan = PlanProgress(entries: session.state.plan)
        // Each child is a section of the surface, with a rule between it and the next.
        return ComposerSurface(isFloating: true, isDropTargeted: isDropTargeted) {
            // While commands are listed, they take the place of the sections above the draft.
            if commands.isEmpty {
                if !session.queuedPrompts.isEmpty {
                    QueuedPromptsSection(
                        prompts: session.queuedPrompts,
                        editing: editingQueued,
                        // After a cancelled turn the queue waits, idle, until one is sent by hand.
                        sendNow: isWorking ? (session.supportsSteering ? .steer : nil) : .send,
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
            inputSection(commands: commands)
            ComposerControlsRow(
                settings: settings,
                resumedAutonomy: autonomyBeforePlan,

                followUpHint: isWorking ? FollowUpHint(preferred: followUp, supportsSteering: session.supportsSteering, agentName: session.agentName) : nil,
                isModelPickerOpen: $isModelPickerOpen,
                onAttach: insertMentions,
                onSet: set,
                onCycleEffort: { apply(settings.nextEffort) },
                onCycleAutonomy: { apply(settings.nextAutonomy) },
                onTogglePlan: { apply(settings.togglingPlan(resumedAutonomy: autonomyBeforePlan)) },
                context: { ContextIndicator(session: session, style: .labeled) }
            )
            .disabled(!canEdit)
        }
        .dropDestination(for: URL.self) { urls, _ in
            insertMentions(urls)
            return !urls.isEmpty
        } isTargeted: {
            isDropTargeted = $0
        }
        .animation(.dsStandard, value: plan.isActive)
        .animation(.dsStandard, value: showsNextSteps)
        .animation(.dsStandard, value: session.queuedPrompts)
    }

    private func inputSection(commands: [AvailableCommand]) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ComposerEditor(text: $session.draft, placeholder: placeholder, isFocused: $isFocused) { press in
                handleKey(press, commands: commands)
            }
            .disabled(!canEdit)
            // One slot for Send and Stop, always reserved, so neither moves nor reflows the text when
            // they swap (the reference app shows Send only once there's a draft, Stop while the agent works).
            ZStack {
                if session.canCancel {
                    ComposerStopButton(isEscapeEnabled: commands.isEmpty) {
                        Task { await session.cancel() }
                    }
                } else if !session.draft.isEmpty {
                    // Disabled rather than hidden when something blocks sending; the toast says why.
                    ComposerSendButton { submit(followUp) }
                        .disabled(!session.canSend && blocker != nil)
                }
            }
            .frame(width: DS.Size.composerAction, height: DS.Size.composerAction)
            .padding(DS.Space.md)
            .transition(.opacity)
        }
        .frame(minHeight: DS.Size.composerInputMinHeight)
        .background {
            // ⌘. stops the turn too; a button takes one shortcut, so this one is invisible.
            if session.canCancel {
                Button("Stop") { Task { await session.cancel() } }
                    .keyboardShortcut(".", modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(.dsQuick, value: session.draft.isEmpty)
        .animation(.dsQuick, value: session.canCancel)
    }

    /// What the last action did; else, while there's a draft, why it can't go out.
    @ViewBuilder
    private var toast: some View {
        if let feedback {
            let onUndo: (() -> Void)? = feedback.canUndo ? { undo() } : nil
            ComposerToast(message: feedback.message, tone: feedback.tone, onUndo: onUndo)
                .id(feedback.id)
                .transition(.opacity)
        } else if let blocker, !session.draft.isEmpty {
            ComposerToast(message: blocker.message, tone: .problem)
                .transition(.opacity)
        }
    }

    /// Says what typing here will do: start work, queue or steer a follow-up, or nothing yet and why.
    private var placeholder: String {
        let agent = session.agentName
        let text = switch session.phase {
        case .loading: "Waiting for session…"
        case .disconnected: "\(agent) isn’t running"
        case .prompting where session.needsApproval: "\(agent) is waiting for your approval…"
        case .prompting where followUp == .steer && session.supportsSteering: "Steer \(agent)’s current turn…"
        case .prompting: "Queue a follow-up for \(agent)…"
        case .idle where session.state.items.isEmpty: "What would you like \(agent) to work on?"
        case .idle: "Message \(agent), or type / for commands"
        }
        // As in the reference app: how to get back here without the mouse.
        guard canEdit, !isFocused, ComposerPlatform.showsKeyboardHints else { return text }
        return "\(text)  ⌘L to focus"
    }

    /// Takes focus when the app asks (⌘L, a click on the session in the sidebar), then clears the ask.
    private func takeFocusIfWanted() {
        guard session.wantsComposerFocus else { return }
        isFocused = true
        session.wantsComposerFocus = false
    }

    // MARK: - Keyboard

    private func handleKey(_ press: KeyPress, commands: [AvailableCommand]) -> KeyPress.Result {
        guard let key = ComposerKeyMap.Key(press.key) else { return .ignored }
        let context = ComposerKeyMap.Context(
            isCommandListOpen: !commands.isEmpty,
            isDraftEmpty: session.draft.isEmpty,
            isWorking: isWorking,
            hasQueuedPrompts: !session.queuedPrompts.isEmpty,
            hasLastPrompt: session.state.lastPrompt != nil,
            preferredFollowUp: followUp
        )
        let modifiers = ComposerKeyMap.Modifiers(press)
        guard let action = ComposerKeyMap.action(for: key, modifiers: modifiers, isRepeat: press.phase == .repeat, in: context) else {
            return .ignored
        }
        if case .moveFocus(let forward) = action {
            return ComposerPlatform.moveKeyFocus(forward: forward) ? .handled : .ignored
        }
        perform(action, commands: commands)
        return .handled
    }

    private func perform(_ action: ComposerKeyMap.Action, commands: [AvailableCommand]) {
        switch action {
        case .moveHighlight(let delta):
            highlighted = min(max(highlighted + delta, 0), commands.count - 1)
        case .insertHighlightedCommand:
            if commands.indices.contains(highlighted) {
                insert(commands[highlighted])
            }
        case .closeCommandList:
            commandsDismissed = true
        case .recallLastPrompt:
            session.draft = session.state.lastPrompt ?? ""
        case .editLastQueuedPrompt:
            if let last = session.queuedPrompts.last {
                edit(last)
            }
        case .submit(let behavior):
            submit(behavior)
        // Focus moves in `handleKey`, which needs to know whether it did.
        case .moveFocus, .swallow:
            break
        }
    }

    // MARK: - Actions

    private func draftChanged() {
        highlighted = 0
        if SlashCommandQuery(draft: session.draft) == nil {
            commandsDismissed = false
        }
        if session.draft.isEmpty {
            editingQueued = nil
        }
    }

    /// Sends the draft; while the agent works, queues or steers it, or saves the queued message
    /// being edited. Says what happened, or why nothing could.
    private func submit(_ behavior: FollowUpBehavior) {
        let text = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let blocker {
            feedback = .blocked(blocker)
            return
        }
        if let id = editingQueued, session.queuedPrompts.contains(where: { $0.id == id }) {
            session.updateQueued(id, text: text)
            editingQueued = nil
            session.draft = ""
            feedback = .updatedInQueue
            return
        }
        // The queued message may have gone out while it was being edited; then it's a new message.
        editingQueued = nil
        if session.canSend {
            // It starts a turn, which the transcript shows.
            Task { await session.submit(behavior) }
            return
        }
        session.draft = ""
        Task {
            do {
                let delivery = try await session.submit(text, behavior)
                feedback = ComposerFeedback(delivery: delivery, requested: behavior, supportsSteering: session.supportsSteering, agentName: session.agentName)
            } catch {
                // Nothing went out, so the message comes back to be sent again.
                if session.draft.isEmpty {
                    session.draft = text
                }
                feedback = .failed(error)
            }
        }
    }

    private func insert(_ command: AvailableCommand) {
        session.draft = SlashCommandQuery.draft(inserting: command)
        isFocused = true
    }

    private func edit(_ prompt: SessionModel.QueuedPrompt) {
        editingQueued = prompt.id
        session.draft = prompt.text
        isFocused = true
    }

    private func remove(_ id: SessionModel.QueuedPrompt.ID) {
        if editingQueued == id {
            editingQueued = nil
            session.draft = ""
        }
        session.removeQueued(id, undoManager: undoManager)
        feedback = .removedFromQueue
    }

    private func undo() {
        undoManager?.undo()
        feedback = nil
    }

    private func set(_ setting: SelectSetting, to value: String) {
        Task { await session.setConfigOption(setting.option, to: value) }
    }

    private func apply(_ change: ComposerSettings.Change?) {
        if let change {
            set(change.setting, to: change.value)
        }
    }

    private func insertMentions(_ urls: [URL]) {
        session.draft = FileMentions.draft(session.draft, mentioning: urls, relativeTo: session.cwd)
        isFocused = true
    }
}
