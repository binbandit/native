import SwiftUI

extension ComposerView {
    func pageSurface(suggestions: ComposerSuggestions?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            ComposerEditor(
                text: $session.draft, selection: $selection,
                placeholder: page?.needsFolder == true
                    ? "Describe the task. You can write it first, and choose the folder after. @ mentions a file, / runs a command."
                    : "Describe the task. @ mentions a file, / runs a command.",
                isFocused: $isFocused, hidesCaret: selectedAttachmentIndex != nil,
                font: DS.ComposeTask.editorFont, lineSpacing: DS.ComposeTask.editorLineSpacing,
                richLineLeading: DS.ComposeTask.editorRichLineLeading,
                insets: DS.ComposeTask.editorInsets, maximumHeight: DS.ComposeTask.editorMaxHeight,
                // A mentioned file shows as its name on a chip, even where @ can't look files up (another Mac).
                referencesEnabled: true
            ) { press in
                handleKey(press, suggestions: suggestions)
            }
            .onAttachmentPaste(isEnabled: isFocused, perform: attach)
            if !session.attachments.isEmpty || !pendingAttachments.isEmpty {
                ComposerAttachmentsSection(
                    attachments: session.attachments, pending: pendingAttachments, missing: missingAttachments,
                    selected: selectedAttachment, capabilities: session.promptCapabilities,
                    agentName: session.agentName,
                    onRemove: removeAttachment)
            }
            if page?.isSealed != true {
                AttachButton(
                    isPickingFiles: $isPickingFiles, onPick: attach, isPage: true,
                    showsPageHint: session.attachments.isEmpty
                )
                .fileDialogDefaultDirectory(session.cwd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dropDestination(for: ComposerDropItem.self) { items, _ in
            attach(items)
            return !items.isEmpty
        } isTargeted: {
            isDropTargeted = $0
        }
    }
}

#if DEBUG
#Preview("Composer - Page with code and attachment") {
    let app = AppModel.preview()
    DSPreviewPair {
        if let session = SessionModel.preview(in: app) {
            let _ = { session.draft = "Show the offline state in `HostDevicePill.swift`, in light and dark." }()
            ComposerView(session: session, page: .init(start: {}, attachmentsPending: { _ in }))
                .environment(app)
                .environment(ComposeTaskPreviewFixtures.automation())
                .frame(width: DS.ComposeTask.width)
                .padding(DS.Space.xxl)
        }
    }
}
#endif
