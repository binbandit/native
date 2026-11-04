import ACP
import Modes
import NativeAutomation
import NativePolicy
import SwiftUI

/// The shared field for new tasks and follow-ups. Submission always goes through the session.
struct ComposerView: View {
    @Bindable var session: SessionModel
    var page: ComposerPageConfiguration? = nil
    var taskModes: TaskModes = .shared
    @State var fieldMenu: ComposerBottomRow.Menu?
    @State var fieldFileQuery: String?
    @State var fieldGoalEditorOpen = false
    @Environment(\.undoManager) var undoManager
    @Environment(\.composerOverlayDismissal) var overlayDismissal
    @Environment(\.windowClaimsCancelKeys) var windowClaimsCancelKeys
    @Environment(\.transcriptColumnMaxWidth) var columnWidth
    @Environment(AutomationCenter.self) var automation
    @Environment(AppModel.self) var app
    @Environment(ComposerDropInbox.self) var drops: ComposerDropInbox?
    @FocusState var isFocused: Bool
    @State var agentCommandDraft: String?
    @State var mentionSource: FileMentionSource?
    @State var isContextUseOpen = false
    @State var isDropTargeted = false
    @State var isPickingFiles = false
    @State var feedback: ComposerFeedback?
    @State var pendingAttachments: [ComposerPendingAttachment] = []
    @State var missingAttachments: Set<PromptAttachment.ID> = []
    @State var selectedAttachment: PromptAttachment.ID?

    var draftText: String {
        get { session.composerMessage }
        nonmutating set { session.composerMessage = newValue }
    }

    var canEdit: Bool { session.phase != .disconnected }
    var isWorking: Bool { session.phase == .prompting }
    var hasContent: Bool { !session.draft.isEmpty || !session.attachments.isEmpty }
    var hasPendingRequest: Bool {
        page == nil && (!session.permissionRequests.isEmpty || session.pendingQuestion != nil)
    }

    var nativeCommands: [ComposerSlashCommand] {
        var commands: [ComposerSlashCommand] = []
        if page == nil, session.origin == .user, !session.isSubagent {
            commands.append(.init(native: ClearConversationCommand.name, description: ClearConversationCommand.summary))
        }
        if automation.goal(for: session) != nil {
            commands.append(.init(native: "goal", description: GoalCommand.usage))
        }
        return commands
    }

    var body: some View {
        fieldSurface
            .frame(maxWidth: page != nil ? DS.ComposeTask.width : columnWidth)
            .padding(.horizontal, page == nil ? DS.Space.xxl : 0)
            .padding(.top, page == nil ? DS.Space.md : 0)
            .padding(.bottom, page == nil ? DS.Space.xl : 0)
            .frame(maxWidth: .infinity)
            .onAppear {
                app.restoreAgentModelChoice(for: session)
                if session.isTranscriptEmpty, session.phase != .loading, !hasPendingRequest { isFocused = true }
                takeFocusIfWanted()
            }
            .onChange(of: session.draft) {
                if session.draft.isEmpty {
                    session.editingQueuedPrompt = nil
                    agentCommandDraft = nil
                }
            }
            .onChange(of: pendingAttachments.isEmpty) { _, empty in page?.attachmentsPending(!empty) }
            .onChange(of: isFocused) { _, focused in
                if !focused { selectedAttachment = nil }
            }
            .task(id: feedback?.id) {
                guard let shown = feedback else { return }
                try? await Task.sleep(for: shown.duration)
                if feedback?.id == shown.id { feedback = nil }
            }
            .onChange(of: session.wantsComposerFocus) { takeFocusIfWanted() }
            .onChange(of: session.isModelPickerRequested, initial: true) { _, requested in
                guard requested else { return }
                fieldMenu = .agent
                session.isModelPickerRequested = false
                session.isAgentPickerRequested = false
            }
            .onChange(of: drops?.items.isEmpty == false) { _, hasDrops in
                guard hasDrops, let drops else { return }
                attach(drops.items)
                drops.items = []
            }
            .onChange(of: session.isAttachmentPickerRequested, initial: true) { _, requested in
                guard requested else { return }
                isPickingFiles = true
                session.isAttachmentPickerRequested = false
            }
            .onChange(of: session.diffCommentAnnouncementGeneration) {
                AccessibilityNotification.Announcement(session.diffCommentAnnouncement).post()
            }
            .onChange(of: session.diffCommentStatus) { _, status in
                if let status { AccessibilityNotification.Announcement(status).post() }
            }
            .onChange(of: PolicyCenter.shared.policy.sourceExcerptsRetentionEnabled) {
                session.enforceDiffCommentRetention()
            }
    }

    var placeholder: String {
        ComposerPlaceholder(
            phase: session.phase, agentName: session.agentName,
            hasQuestion: session.pendingQuestion != nil, needsApproval: session.needsApproval,
            isStopping: session.isStopping, isNewSession: session.isTranscriptEmpty,
            showsFocusHint: canEdit && !isFocused && ComposerPlatform.showsKeyboardHints
        ).text
    }

    func takeFocusIfWanted() {
        // A mounted ask owns the shared focus request until its answer editor consumes it.
        guard session.wantsComposerFocus, !hasPendingRequest else { return }
        isFocused = true
        session.wantsComposerFocus = false
    }

    func agentChangeReceipt(_ change: ComposerAgentChange) -> some View {
        ComposerAgentReceiptSection(change: change) { fieldMenu = .mode }
    }
}

extension FocusedValues {
    @Entry var contextUsePopover: Binding<Bool>?
}
