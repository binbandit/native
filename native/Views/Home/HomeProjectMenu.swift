import SwiftUI

/// The quiet link under the agent cards: the project their tasks start in, as a menu for choosing
/// another or adding one. It sits where Conductor puts a ghost button, and reads as the cards'
/// context ("in native") rather than as another action.
struct HomeProjectMenu<ID: Hashable>: View {
    let projects: [HomeProject<ID>]
    @Binding var selection: ID
    let onAddProject: () -> Void

    @State private var isHovered = false

    private var selected: HomeProject<ID>? {
        projects.first { $0.id == selection }
    }

    var body: some View {
        Menu {
            Section("New Tasks Start In") {
                ForEach(projects) { project in
                    Toggle(isOn: Binding(get: { selection == project.id }, set: { if $0 { selection = project.id } })) {
                        Text(project.name)
                        Text(project.location)
                    }
                }
            }
            Divider()
            Button("Open Folder…", action: onAddProject)
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "folder")
                    .font(HomeLayout.cardGlyph)
                Text(selected?.name ?? "Choose a Project")
                    .font(.dsBody)
                    .tracking(DS.Tracking.tight)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.dsTextTertiary)
            }
            .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.md + DS.Space.xxs)
            .frame(minHeight: max(DS.Size.controlSM, DS.Size.minimumHitTarget))
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(isHovered ? .dsHover : .clear)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .trackHover($isHovered)
        .accessibilityLabel("New Tasks Start In")
        .accessibilityValue(selected?.name ?? "No Project")
        .help(selected.map { "New tasks start in \($0.url.path(percentEncoded: false))" } ?? "Choose a Project")
    }
}
