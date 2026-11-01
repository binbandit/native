import ACP
import SwiftUI
import UniformTypeIdentifiers

extension ComposerView {
    var fieldSurface: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            // Part C will replace these sections. Keep their existing actions and presentation here.
            if let question = session.pendingQuestion {
                AgentQuestionDock(session: session, question: question).id(question.id)
            }
            if !session.queuedPrompts.isEmpty {
                QueuedPromptsSection(
                    prompts: session.queuedPrompts, editing: session.editingQueuedPrompt,
                    sendNow: session.sendNowRoute, agentName: session.agentName,
                    onSendNow: { sendNow($0) }, onMove: { session.moveQueued($0, $1) },
                    onDrop: { session.moveQueued($0, before: $1) }, onEdit: edit, onRemove: remove)
            }
            if let change = session.modelChange { agentChangeReceipt(change) }
            ComposerField(
                text: Binding(get: { draftText }, set: { draftText = $0 }),
                isFocused: Binding(get: { isFocused }, set: { isFocused = $0 }),
                openMenu: $fieldMenu, state: fieldRowState, actions: fieldActions,
                placeholder: placeholder,
                files: fieldFileQuery.flatMap { mentionSource?.matches(for: $0) } ?? [],
                commands: nativeCommands + session.availableCommands.map(ComposerSlashCommand.init),
                isDropTargeted: isDropTargeted || drops?.isTargeted == true,
                onQuery: { fieldFileQuery = page?.allowsFileMentions == false ? nil : $0 },
                onCommand: { agentCommandDraft = $0.isNative ? nil : draftText },
                onAttachments: attachFieldItems,
                onEscape: {
                    if let overlayDismissal { overlayDismissal.dismiss(); return true }
                    guard session.canCancel, !windowClaimsCancelKeys else { return false }
                    stop()
                    return true
                }
            ) {
                fieldAttachments
            }
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

    private var fieldRowState: ComposerRowState {
        var state = ComposerRowModelAdapter(app: app, session: page == nil ? session : nil).state
        state.disabledReason =
            session.diffCommentSendBlock ?? session.sendBlockedReason ?? attachmentsBlockedReason
            ?? (hasContent ? nil : "Write a message or attach a file")
        return state
    }

    private var fieldActions: ComposerRowActions {
        ComposerRowModelAdapter(app: app, session: page == nil ? session : nil, undoManager: undoManager).actions(
            attach: { isPickingFiles = true }, context: { isContextUseOpen = true }, send: { submit(.queue) })
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
