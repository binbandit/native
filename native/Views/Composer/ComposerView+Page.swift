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
                insets: DS.ComposeTask.editorInsets, maximumHeight: DS.ComposeTask.editorMaxHeight
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
            HStack(spacing: DS.Space.sm) {
                AttachButton(isPickingFiles: $isPickingFiles, onPick: attach, isPage: true)
                if session.attachments.isEmpty {
                    Text("Attach files, or drop them anywhere on the page")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .fileDialogDefaultDirectory(session.cwd)
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
