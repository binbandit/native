import SwiftUI

/// The bar at the foot of the sidebar while tasks are picked (or in select mode on touch): how many,
/// the common actions at hand, the rest in More, and Done.
struct SidebarSelectionBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let selection: SidebarSelectionModel

    var body: some View {
        let keys = selection.keys
        let actions = model.bulkAvailability(of: keys)
        HStack(spacing: DS.Space.xxs) {
            Text(keys.isEmpty ? "Pick tasks" : "\(keys.count) selected")
                .font(.dsCalloutMedium)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
                .padding(.leading, DS.Space.sm)
            Spacer(minLength: DS.Space.xs)
            if actions.canUnarchive, !actions.canArchive {
                IconButton("Unarchive", systemImage: "arrow.uturn.backward") {
                    Task { await model.unarchiveSessions(keys) }
                }
            } else {
                IconButton("Archive", systemImage: "archivebox") {
                    selection.clear()
                    Task { await model.archiveSessions(keys, undoManager: undoManager) }
                }
                .disabled(!actions.canArchive)
            }
            IconButton(
                actions.canMarkRead ? "Mark as Read" : "Mark as Unread",
                systemImage: actions.canMarkRead ? "envelope.open" : "envelope.badge"
            ) {
                model.setUnread(keys, !actions.canMarkRead)
            }
            .disabled(keys.isEmpty)
            IconButton("Delete…", systemImage: "trash") { selection.isConfirmingDelete = true }
                .disabled(keys.isEmpty)
            Menu {
                SidebarBulkMenu(selection: selection)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                    .contentShape(.rect)
                    .dsHitTarget(DS.Size.controlXS)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.dsTextSecondary)
            .disabled(keys.isEmpty)
            .help("More Actions")
            .accessibilityLabel("More Actions")
            Button("Done") { selection.clear() }
                .buttonStyle(.ds(.ghost))
                .help("Deselect All (Escape)")
        }
        .padding(DS.Space.xs)
        .background(.dsHover, in: .rect(cornerRadius: DS.Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .strokeBorder(.dsBorder, lineWidth: 1)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.bottom, DS.Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(keys.isEmpty ? "Selecting tasks" : "\(keys.count) tasks selected")
    }
}
