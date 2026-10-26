import SwiftUI
import TaskList

/// The fixed action is a direct chooser button; recents are a separate keyboard and touch stop.
struct SidebarFolderActions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @FocusState private var isOpenFocused: Bool
    @State private var showsRecents = false
    @State private var isHovered = false
    @State private var actionWidth = DS.Size.sidebarWidth - 2 * DS.Sidebar.inset

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarFolderResult()
            HStack(spacing: 0) {
                Button(action: model.requestOpenFolder) {
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: model.canOpenFolders ? "folder" : "lock")
                            .font(.system(size: DS.Size.statusGlyph))
                            .frame(width: DS.Size.rowLeading)
                        Text("Open Folder…").font(.dsCalloutBook)
                        Spacer(minLength: 0)
                        if let key = CommandRegistry.shared.keyboardShortcut(for: .projectOpen) {
                            Text(key.displayString).font(DS.Sidebar.keycapFont).foregroundStyle(.dsTextTertiary)
                        }
                    }
                    .padding(.leading, DS.Sidebar.leading)
                    .padding(.trailing, DS.Space.md)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: DS.isTouchPlatform ? DS.Size.minimumHitTarget : DS.Sidebar.rowHeight
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .dsFocusShape(.rect(cornerRadius: DS.Radius.control))
                .disabled(!model.canOpenFolders || !model.sidebarFolders.opening.isEmpty)
                .focusable()
                .focused($isOpenFocused)
                .accessibilityLabel("Open Folder")
                .accessibilityHint("Choose a folder to add to Native")
                .help("Open Folder… (⌘O)")
                Button {
                    showsRecents.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(DS.Sidebar.foldChevronFont)
                        .foregroundStyle(.dsTextTertiary)
                        .frame(
                            width: DS.isTouchPlatform ? DS.Size.minimumHitTarget : DS.Size.controlXS,
                            height: DS.isTouchPlatform ? DS.Size.minimumHitTarget : DS.Size.controlXS
                        )
                        .overlay(alignment: .leading) { SeparatorLine(axis: .vertical) }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .dsFocusShape(.rect(cornerRadius: DS.Radius.control))
                .focusable()
                .accessibilityLabel("Recent Folders")
                .accessibilityValue("\(model.sidebarFolders.history.entries.count) folders")

            }
            .foregroundStyle(.dsTextSecondary)
            .background(
                showsRecents ? Color.dsSelected : isHovered ? Color.dsHover : .clear,
                in: .rect(cornerRadius: DS.Radius.row)
            )
            .trackHover($isHovered)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { actionWidth = $0 }
            .modifier(
                PlatformFolderRecentsPopover(
                    isPresented: $showsRecents,
                    attachmentAnchor: .point(
                        UnitPoint(
                            x: min(1, (DS.SidebarFolders.recentsWidth / 2 + DS.Space.xxs) / max(1, actionWidth)), y: 0))
                ) {
                    SidebarFolderRecents { showsRecents = false }
                }
            )
            .padding(.horizontal, DS.Sidebar.inset)
            .padding(.top, DS.Space.sm)
            .padding(.bottom, DS.Space.md)
        }
        #if DEBUG
        .onAppear {
            if ["F2", "F9"].contains(SidebarFolderPreviewFixtures.requested ?? "") { showsRecents = true }
            if SidebarFolderPreviewFixtures.requested == "F8" { isOpenFocused = true }
        }
        #endif
    }
}

#if DEBUG
#Preview("Folder actions - Rest") {
    DSPreviewPair { SidebarFolderActions().frame(width: DS.Size.sidebarWidth) }
        .sidebarPreviewEnvironment(AppModel.preview())
}
#endif
