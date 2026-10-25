import SwiftUI

/// The title popover, as a Mac document window has: the task's name to edit, then the facts
/// that identify it, and who manages them. Return keeps the name, Escape puts it back, and
/// clicking away keeps it, as renaming in the sidebar does. An empty name goes back to the
/// automatic title.
struct TaskWellTitlePopover: View {
    let facts: TaskWellTitleFacts
    let rename: (String) -> Void
    let close: () -> Void
    @State private var draft = ""
    @State private var isCancelled = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Full-width rules between the name, its facts and who manages them, as in the open well.
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                label("Name")
                nameField
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.lg)
            SeparatorLine()
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.md, verticalSpacing: DS.Space.md) {
                fact("Project", Text(facts.project))
                if let branch = facts.branch {
                    fact("Branch", Text(branch).font(DS.TaskWell.object))
                }
                fact("Runs on", Text(facts.machine ?? "This Mac"))
                fact(
                    "Agent",
                    Text(
                        "\(facts.agent)\(Text(facts.model.map { " · \($0)" } ?? "").foregroundStyle(.dsTextTertiary))"),
                    isManaged: facts.isWorkerManaged)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.lg)
            if let management = facts.management {
                SeparatorLine()
                Label(management, systemImage: "lock")
                    .font(DS.TaskWell.caption)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Space.xl)
                    .frame(minHeight: DS.TaskWell.footerHeight, alignment: .leading)
            }
        }
        .frame(width: DS.TaskWell.titlePanelWidth)
        // The open well's backdrop, so their rules read the same.
        .dsPopoverBackground()
        .onAppear {
            draft = facts.title
            isFocused = true
        }
        .onDisappear {
            if !isCancelled, draft != facts.title { rename(draft) }
        }
    }

    private var nameField: some View {
        TextField("Name", text: $draft, prompt: Text("Named from the conversation"))
            .textFieldStyle(.plain)
            .font(.dsCalloutBook)
            .foregroundStyle(.dsTextPrimary)
            .focused($isFocused)
            .padding(.horizontal, DS.Space.md)
            .frame(height: DS.Size.controlSM)
            .background(.dsBackground, in: .rect(cornerRadius: DS.Radius.row, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .strokeBorder(isFocused ? .dsBorderHover : .dsBorder)
            }
            .accessibilityLabel("Task name")
            .accessibilityIdentifier("taskWell.title.name")
            .onSubmit(close)
            .onKeyPress(.escape) {
                isCancelled = true
                close()
                return .handled
            }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(DS.TaskWell.body)
            .foregroundStyle(.dsTextTertiary)
            .frame(width: DS.TaskWell.titleLabelWidth, alignment: .trailing)
    }

    private func fact(_ title: String, _ value: Text, isManaged: Bool = false) -> some View {
        GridRow {
            label(title)
            HStack(spacing: DS.Space.sm) {
                value
                    .font(DS.TaskWell.body)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if isManaged {
                    Image(systemName: "lock")
                        .font(DS.TaskWell.body)
                        .foregroundStyle(.dsTextTertiary)
                        .accessibilityLabel("Managed")
                }
            }
        }
    }
}

#if DEBUG
#Preview("Well - Title popover, remote, managed") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ForEach(
                [
                    TaskWellPreviewFixtures.title, TaskWellPreviewFixtures.remoteTitle,
                    TaskWellPreviewFixtures.managedTitle,
                ],
                id: \.title
            ) { facts in
                TaskWellTitlePopover(facts: facts, rename: { _ in }, close: {})
            }
        }
    }
}
#endif
