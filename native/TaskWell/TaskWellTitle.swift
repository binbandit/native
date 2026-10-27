import SwiftUI

/// What the title says about a task: its name, then where it lives, and in its popover who runs it.
struct TaskWellTitleFacts: Equatable {
    var title: String
    var project: String
    var branch: String?
    /// The machine's name when it isn't this Mac.
    var machine: String?
    var agent: String
    var model: String?
    /// The organization fixes the agent, its environment or where it runs.
    var isWorkerManaged = false
    var management: String?
}

/// The task's identity at the toolbar's leading edge, where a Mac document window has its title:
/// the name over its project and branch, and the machine when it isn't this Mac. Clicking it
/// opens the title popover to rename the task.
struct TaskWellTitle: View {
    let facts: TaskWellTitleFacts
    @Binding var isPresented: Bool
    var reportsIdealWidth: (CGFloat) -> Void = { _ in }
    var moveToProject: (() -> Void)?
    let rename: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .help("Rename the task and see where it runs")
        .accessibilityLabel(Text("\(facts.title), \(subtitle)"))
        .accessibilityHint("Renames the task")
        .accessibilityIdentifier("taskWell.title")
        .dsPopover(isPresented: $isPresented, arrowEdge: .bottom) {
            TaskWellTitlePopover(facts: facts, rename: rename, moveToProject: moveToProject) { isPresented = false }
        }
        // Where the window draws its own title.
        .padding(.leading, DS.Space.xl)
        .background {
            label.fixedSize().hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { reportsIdealWidth($0 + DS.Space.xl) }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(DSInlineCode.plain(facts.title))
                .font(.dsCalloutSemibold)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(1)
            HStack(spacing: DS.Space.xs) {
                Text(facts.project).lineLimit(1)
                if let branch = facts.branch {
                    Image(systemName: "arrow.triangle.branch")
                        .imageScale(.small)
                        .foregroundStyle(.dsTextQuaternary)
                    Text(branch).lineLimit(1).truncationMode(.middle)
                }
                if let machine = facts.machine {
                    Text("·").foregroundStyle(.dsTextQuaternary)
                    Image(systemName: "macmini")
                        .imageScale(.small)
                        .foregroundStyle(.dsTextQuaternary)
                    Text(machine).lineLimit(1)
                }
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xxs)
        .background(
            isHovered || isPresented ? Color.dsHover : .clear,
            in: .rect(cornerRadius: DS.Radius.row, style: .continuous)
        )
        // The fill reaches past the text, so the text stays where the window's title would be.
        .padding(.horizontal, -DS.Space.sm)
        .contentShape(.rect)
        .trackHover($isHovered)
    }

    private var subtitle: String {
        [facts.project, facts.branch, facts.machine.map { "on \($0)" }].compactMap { $0 }.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Well - Title on this Mac, on another machine, and long") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            TaskWellTitle(facts: TaskWellPreviewFixtures.title, isPresented: .constant(false)) { _ in }
            TaskWellTitle(facts: TaskWellPreviewFixtures.remoteTitle, isPresented: .constant(false)) { _ in }
            TaskWellTitle(facts: TaskWellPreviewFixtures.longTitle, isPresented: .constant(false)) { _ in }
                .frame(maxWidth: 200, alignment: .leading)
        }
        .padding(.vertical, DS.Space.lg)
    }
}
#endif
