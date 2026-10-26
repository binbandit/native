import ACP
import SwiftUI

struct DiffCommentsEditor: View {
    let session: SessionModel
    let quote: PromptQuote
    var isInline = true
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focused: Bool

    private var id: UUID? { quote.comment?.id }
    private var bodyText: String {
        session.diffCommentEditors.first { $0.comment?.id == id }?.comment?.body ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Text(session.diffComments.contains { $0.comment?.id == id } ? "Edit comment" : "New comment")
                Text(DiffCommentsSourceQuote.label(quote))
            }
            .font(DS.ComposerQuote.headerFont)
            .foregroundStyle(.dsTextSecondary)
            TextEditor(
                text: Binding(
                    get: { bodyText },
                    set: { text in
                        if let id { session.updateDiffComment(id, body: text) }
                    })
            )
            .font(.dsCallout)
            .scrollContentBackground(.hidden)
            .padding(.vertical, DS.Space.md)
            .padding(.horizontal, DS.DiffComments.editorHorizontal)
            .frame(height: DS.DiffComments.editorMinHeight)
            .background(.dsSurface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
            .overlay { RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(.dsBorderStrong) }
            .dsFocusShape(RoundedRectangle(cornerRadius: DS.Radius.control))
            .focused($focused)
            .accessibilityLabel("Comment on \(quote.source), \(DiffCommentsSourceQuote.label(quote))")
            .onKeyPress(.escape) {
                session.collapseDiffComment()
                return .handled
            }
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.contains(.command), let id else { return .ignored }
                session.addDiffComment(id, undoManager: undoManager)
                return .handled
            }
            HStack(spacing: DS.Space.md) {
                Text("Kept as a draft")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
                Spacer(minLength: DS.Space.xs)
                Button("Cancel") { session.collapseDiffComment() }
                    .buttonStyle(.ds(.ghost))
                Button("Add Comment ⌘↩") {
                    if let id { session.addDiffComment(id, undoManager: undoManager) }
                }
                .buttonStyle(.ds(.primary))
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add Comment to Draft")
            }
            if session.diffCommentStatus == "Add this comment before sending" {
                Text("Add this comment before sending").font(.dsCaption).foregroundStyle(.dsDanger)
            }
        }
        .padding(.leading, DS.Space.lg)
        .overlay(alignment: .leading) { Rectangle().fill(.dsBorderStrong).frame(width: DS.DiffComments.hairline) }
        .padding(.leading, isInline ? DS.DiffComments.anchorInset : 0)
        .padding(.trailing, isInline ? DS.Space.xl : 0)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.xl)
        .contextMenu {
            Button("Discard Draft Comment") {
                if let id { session.discardDiffComment(id, undoManager: undoManager) }
            }
        }
        .task {
            await Task.yield()
            focused = true
        }
        .onChange(of: session.diffCommentFocusRequest) { focused = true }
    }
}

#if DEBUG
#Preview("DiffCommentsEditor - States") {
    DSPreviewPair {
        DiffCommentsPreviewHost("C3") { session in
            if let quote = session.diffCommentEditors.first {
                DiffCommentsEditor(session: session, quote: quote).frame(width: DS.DiffComments.referencePaneWidth)
            }
        }
    }
}
#endif
