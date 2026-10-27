import SwiftUI

struct SidebarFolderOpeningRow: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.md) {
                DotGridLoader(pattern: .settingUp).frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                Text(name).font(DS.Sidebar.projectFont).foregroundStyle(.dsTextSecondary)
            }
            Text("Opening folder…").font(.dsBody).foregroundStyle(.dsTextSecondary)
        }
        .padding(.leading, DS.Sidebar.headerLeading)
        .padding(.top, DS.Sidebar.headerTop)
        .accessibilityLabel("Opening \(name)")
    }
}

#if DEBUG
#Preview("Folder row - Opening") {
    DSPreviewPair { SidebarFolderOpeningRow(name: "atlas").frame(width: DS.Size.sidebarWidth) }
}
#endif
