import SwiftUI

/// Edits a session's title in place of its row, keeping the row's glyphs where they were: Return
/// keeps the edit, Escape throws it away, clicking elsewhere keeps it (as in the Finder), and an
/// empty title goes back to the automatic one.
struct SessionTitleField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let summary: SessionSummary
    let status: TaskStatus

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        // Mirrors `TaskRow`'s layout so the title doesn't jump when editing starts.
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: summary.agent.symbolName)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                .padding(.top, DS.Space.xxs)
            StatusIndicator(status: status)
                .padding(.top, DS.Space.xxs)
                .padding(.trailing, DS.Space.xxs)
            TextField("Title", text: $draft)
                .textFieldStyle(.plain)
                .font(.dsCalloutBook)
                .foregroundStyle(.dsTextPrimary)
                .focused($isFocused)
                .frame(height: 20)
                .accessibilityLabel("Session title")
        }
        .padding(.vertical, DS.Space.md)
        .padding(.leading, TaskRowIndent.grouped.leading)
        .padding(.trailing, DS.Space.sm)
        .background(.dsSelected, in: .rect(cornerRadius: DS.Radius.row, style: .continuous))
        .onAppear {
            draft = model.title(for: summary)
        }
        .task {
            // A field can only take focus once it's in the window, after it appears.
            isFocused = true
        }
        .onSubmit(commit)
        .onExitCommand {
            model.renaming = nil
        }
        .onChange(of: isFocused) {
            if !isFocused {
                commit()
            }
        }
    }

    private func commit() {
        guard model.renaming == summary.id else { return }
        model.renaming = nil
        let previous = model.title(for: summary)
        guard draft != previous else { return }
        model.rename(summary.id, to: draft)
        let key = summary.id
        undoManager?.registerUndo(withTarget: model) { model in
            model.rename(key, to: previous)
        }
        undoManager?.setActionName("Rename Session")
    }
}
