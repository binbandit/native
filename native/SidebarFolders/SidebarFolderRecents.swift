import SwiftUI
import TaskList

/// The same six successful local folders feed this popover and File > Open Recent.
struct SidebarFolderRecents: View {
    let dismiss: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var highlighted = 0
    @FocusState private var focusedItem: Int?

    var body: some View {
        let entries = model.sidebarFolders.history.entries
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Folders").font(.dsCaption).foregroundStyle(.dsTextTertiary)
                .padding(.leading, DS.SidebarFolders.textLeading)
                .padding(.vertical, DS.Space.sm)
            if entries.isEmpty {
                Text("No recent folders yet.\nFolders you open appear here.")
                    .font(.dsBody).foregroundStyle(.dsTextSecondary)
                    .padding(.leading, DS.SidebarFolders.textLeading)
                    .padding(.vertical, DS.Space.md)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    open(entry)
                } label: {
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "folder").font(.system(size: DS.Size.navIcon))
                            .foregroundStyle(.dsTextTertiary)
                            .frame(width: DS.Size.navIcon)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.url.lastPathComponent).font(DS.ComposerSettings.rowFont).foregroundStyle(
                                .dsTextPrimary)
                            Text(entry.url.deletingLastPathComponent().lastPathComponent)
                                .font(.dsCaption).foregroundStyle(.dsTextTertiary)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.md)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: DS.isTouchPlatform ? DS.Size.minimumHitTarget : DS.SidebarFolders.recentRowHeight
                    )
                    .contentShape(.rect)
                    .background(
                        highlighted == index ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control))
                }
                .buttonStyle(.plain)
                .focused($focusedItem, equals: index)
                .dsFocusShape(.rect(cornerRadius: DS.Radius.control))
                .disabled(!model.canOpenRecentFolder(entry))
                .help(entry.url.path)
                .accessibilityLabel(
                    "\(entry.url.lastPathComponent), \(entry.url.deletingLastPathComponent().lastPathComponent)"
                )
                .accessibilityHint("\(entry.url.path), this device")
                .contextMenu { Button("Locate Folder…") { chooseFolder() } }
            }
            SeparatorLine().padding(.top, DS.Space.xs)
            Button(action: chooseFolder) {
                HStack {
                    Text("Choose Folder…")
                    Spacer()
                    if let key = CommandRegistry.shared.keyboardShortcut(for: .projectOpen) { Kbd(key) }
                }
                .font(.dsBody).foregroundStyle(.dsTextPrimary)
                .padding(.leading, DS.SidebarFolders.textLeading)
                .padding(.trailing, DS.Space.md)
                .frame(minHeight: DS.isTouchPlatform ? DS.Size.minimumHitTarget : DS.Size.controlSM)
                .background(
                    highlighted == entries.count ? Color.dsSelected : .clear,
                    in: .rect(cornerRadius: DS.Radius.control)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!model.canOpenFolders)
            .focused($focusedItem, equals: entries.count)
            .dsFocusShape(.rect(cornerRadius: DS.Radius.control))
        }
        .padding(DS.Space.sm)
        .frame(width: DS.SidebarFolders.recentsWidth)
        .background(.dsOverlay)
        .onAppear {
            highlighted = navigable.first ?? entries.count; focusedItem = highlighted
        }
        .onChange(of: navigable) { _, items in
            highlighted = items.first ?? entries.count
            focusedItem = items.first
        }
        .onChange(of: focusedItem) { _, item in if let item { highlighted = item } }
        .onKeyPress(.upArrow) {
            move(-1); return .handled
        }
        .onKeyPress(.downArrow) {
            move(1); return .handled
        }
        .onKeyPress(.return) {
            activate(); return .handled
        }
        .onKeyPress(.space) {
            activate(); return .handled
        }
        .onKeyPress(.escape) {
            dismiss(); return .handled
        }
        .accessibilityLabel("Recent Folders")
    }

    private var navigable: [Int] {
        let entries = model.sidebarFolders.history.entries
        return entries.indices.filter { model.canOpenRecentFolder(entries[$0]) }
            + (model.canOpenFolders ? [entries.count] : [])
    }

    private func move(_ offset: Int) {
        guard let index = navigable.firstIndex(of: highlighted) else { return }
        highlighted = navigable[min(navigable.count - 1, max(0, index + offset))]
        focusedItem = highlighted
    }

    private func activate() {
        guard model.canOpenFolders else { return }
        let entries = model.sidebarFolders.history.entries
        if entries.indices.contains(highlighted) { open(entries[highlighted]) } else { chooseFolder() }
    }

    private func open(_ entry: FolderHistory.Entry) {
        dismiss()
        Task { await model.openRecentFolder(entry, undoManager: undoManager) }
    }

    private func chooseFolder() {
        dismiss()
        model.requestOpenFolder()
    }
}

#if DEBUG
#Preview("Recent folders - Populated") {
    let app = AppModel.preview()
    for name in ["native", "pier", "atlas"] { app.sidebarFolders.remember(URL(filePath: "/Development/\(name)")) }
    return DSPreviewPair { SidebarFolderRecents {} }.sidebarPreviewEnvironment(app)
}
#Preview("Recent folders - Empty") {
    DSPreviewPair { SidebarFolderRecents {} }.sidebarPreviewEnvironment(AppModel.preview(.empty))
}
#endif
