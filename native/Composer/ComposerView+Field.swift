import ACP
import NativeAutomation
import SwiftUI
import UniformTypeIdentifiers

extension ComposerView {
    var fieldSurface: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            fieldRequests
            if let change = session.modelChange { agentChangeReceipt(change) }
            fieldFeedback
            fieldQueue
            ComposerField(
                text: Binding(get: { draftText }, set: { draftText = $0 }),
                isFocused: Binding(get: { isFocused }, set: { isFocused = $0 }),
                openMenu: $fieldMenu, editorFocus: $isFocused, state: fieldRowState, actions: fieldActions,
                placeholder: placeholder,
                files: fieldFileQuery.flatMap { mentionSource?.matches(for: $0) } ?? [],
                commands: fieldCommands,
                isDropTargeted: isDropTargeted || drops?.isTargeted == true,
                onQuery: { fieldFileQuery = page?.allowsFileMentions == false ? nil : $0 },
                onCommand: { agentCommandDraft = $0.isNative ? nil : draftText },
                onAttachments: attachFieldItems,
                onEscape: {
                    if let overlayDismissal { overlayDismissal.dismiss(); return true }
                    guard !windowClaimsCancelKeys else { return false }
                    if cancelFieldQueuedEdit() { return true }
                    guard session.canCancel else { return false }
                    stop()
                    return true
                },
                onEvent: handleFieldEvent
            ) {
                fieldAttachments
            }
            .disabled(!canEdit || page?.isSealed == true)
            .textViewDefersDrops(true)
            .onAttachmentPaste(isEnabled: isFocused && canEdit, perform: attach)
            .composerAttachmentDrop(isTargeted: { isDropTargeted = $0 }, perform: attach)
            .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) {
                if case .success(let urls) = $0 { attach(urls) }
            }
            .fileDialogDefaultDirectory(session.cwd)
            .popover(isPresented: $isContextUseOpen, arrowEdge: .bottom) {
                ContextBreakdownView(source: SessionContextSource(session: session)).dsPopoverBackground()
            }
            .focusedSceneValue(\.contextUsePopover, $isContextUseOpen)
            .popover(isPresented: $fieldGoalEditorOpen, arrowEdge: .top) {
                if let controller = automation.goal(for: session) {
                    SessionGoalEditor(controller: controller, agentName: session.agentName) {
                        fieldGoalEditorOpen = false
                    }
                }
            }
            .onChange(of: automation.goal(for: session)?.isEditorRequested, initial: true) { _, requested in
                guard requested == true else { return }
                fieldGoalEditorOpen = true
                automation.goal(for: session)?.isEditorRequested = false
            }
            if session.diffCommentsExpanded, !session.diffComments.isEmpty {
                DiffCommentsComposerSection(session: session)
            }
            if session.diffCommentStatus != nil || session.unresolvedCommentPacket != nil {
                DiffCommentsDeliveryStatus(session: session, retry: { submit(.queue) })
            }
            if session.diffCommentEditsInComposer,
                let editor = session.diffCommentEditors.first(where: { $0.comment?.id == session.activeDiffComment })
            {
                DiffCommentsEditor(session: session, quote: editor, isInline: false)
            }
        }
        .task(id: session.cwd) {
            mentionSource = FileMentionSource(root: session.cwd)
            fieldFileQuery = nil
        }
        .task(id: fieldFileQuery != nil) {
            if fieldFileQuery != nil { await mentionSource?.loadIfNeeded() }
        }
    }

    private func handleFieldEvent(_ event: DSTextInputEvent, selection: NSRange) -> Bool {
        if event.modifiers.isEmpty {
            let key: DraftAttachmentKeys.Key =
                switch event.key {
                case .leftArrow: .left
                case .rightArrow: .right
                case .delete: .backspace
                case .deleteForward: .forwardDelete
                case .escape: .escape
                default: .other
                }
            let attachments = session.attachments
            let outcome = DraftAttachmentKeys.outcome(
                for: key, selection: selectedAttachmentIndex, count: attachments.count,
                draft: .init(isEmpty: draftText.isEmpty, isCaretAtStart: selection == NSRange(location: 0, length: 0)),
                isRepeat: event.isRepeat)
            if let index = outcome.removing, attachments.indices.contains(index) {
                removeAttachment(attachments[index].id)
            }
            selectAttachment(at: outcome.selection)
            if !outcome.passesKey { return true }
        }
        if event.key == .upArrow, event.modifiers.isEmpty, draftText.isEmpty {
            if let last = session.queuedPrompts.last {
                edit(last.id)
                return true
            }
            if !isWorking, let last = session.state.lastPrompt {
                draftText = last
                return true
            }
        }
        if event.modifiers == [.command, .option], let id = session.editingQueuedPrompt {
            if event.key == .upArrow { session.moveQueued(id, .up); return true }
            if event.key == .downArrow { session.moveQueued(id, .down); return true }
        }
        if event.key == .return, event.modifiers == .command {
            guard !event.isRepeat else { return true }
            if let id = session.editingQueuedPrompt {
                if session.sendNowRoute != nil { sendNow(id, savingDraft: true) }
            } else {
                submit(.steer)
            }
            return true
        }
        return event.key == .return && event.modifiers.isEmpty && event.isRepeat
    }

    func cancelFieldQueuedEdit() -> Bool {
        guard session.editingQueuedPrompt != nil else { return false }
        stopEditingQueued()
        return true
    }

    @ViewBuilder
    private var fieldFeedback: some View {
        if let feedback {
            switch feedback.tone {
            case .problem: NoticeBanner(tone: .warning, title: feedback.message)
            case .notice: NoticeBanner(tone: .info, title: feedback.message)
            }
        } else if let blocked = session.sendBlockedReason, hasContent {
            NoticeBanner(tone: .warning, title: blocked)
        }
    }

    private var fieldRowState: ComposerRowState {
        var state = ComposerRowModelAdapter(app: app, session: page == nil ? session : nil).state
        state.disabledReason =
            session.diffCommentSendBlock ?? session.sendBlockedReason ?? attachmentsBlockedReason
            ?? (hasContent ? nil : "Write a message or attach a file")
        return state
    }

    private var fieldActions: ComposerRowActions {
        ComposerRowModelAdapter(app: app, session: page == nil ? session : nil, undoManager: undoManager).actions(
            attach: { isPickingFiles = true }, context: { isContextUseOpen = true }, send: submitField)
    }

    @ViewBuilder
    private var fieldAttachments: some View {
        if !session.attachments.isEmpty || !pendingAttachments.isEmpty {
            ComposerAttachmentsSection(
                attachments: session.attachments, pending: pendingAttachments, missing: missingAttachments,
                selected: selectedAttachment, capabilities: session.promptCapabilities, agentName: session.agentName,
                onRemove: removeAttachment)
        }
        if !session.composerQuotes.isEmpty {
            CappedHeightScrollView(maxHeight: ComposerMetrics.attachmentsMaxHeight) {
                FlowLayout(spacing: DS.Space.sm) {
                    ForEach(Array(session.composerQuotes.enumerated()), id: \.offset) { index, quote in
                        ComposerChip(quote.source, systemImage: quote.comment == nil ? "text.quote" : "text.bubble") {
                            session.removeQuote(at: index, undoManager: undoManager)
                        }
                        .help(quote.comment?.body ?? quote.source)
                        .contextMenu {
                            if quote.comment != nil {
                                Button("Edit Comment") { session.editDiffComment(quote, inComposer: true) }
                            }
                            Button("Remove") { session.removeQuote(at: index, undoManager: undoManager) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.md)
            }
        }
    }

    private func attachFieldItems(_ items: [DSTextInputAttachment]) {
        for item in items {
            switch item {
            case .file(let url): attach([url])
            case .image(let data, let type): attachImage(data, type: UTType(type) ?? .image)
            }
        }
    }
}
