import SwiftUI

struct SidebarFolderDropFeedback: View {
    let names: [String]

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.row)
            .strokeBorder(.dsBorderStrong)
            .padding(DS.Sidebar.inset)
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "folder").font(.system(size: DS.SidebarFolders.dropGlyph))
                        Text(names.count == 1 ? "Add \(names[0])" : "Add \(names.count) folders")
                            .font(.dsCalloutMedium)
                    }
                    .foregroundStyle(.dsTextPrimary)
                    Text(names.count == 1 ? "Release to add this folder." : "Release to add these folders.")
                        .font(DS.ComposerSettings.detailFont).foregroundStyle(.dsTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.xl)
                .background(.dsOverlay, in: .rect(cornerRadius: DS.Radius.row))
                .overlay { RoundedRectangle(cornerRadius: DS.Radius.row).strokeBorder(.dsBorder) }
                .padding(DS.Space.xl)
            }
            .accessibilityLabel(names.count == 1 ? "Add \(names[0]) to Native" : "Add \(names.count) folders to Native")
    }
}

#if DEBUG
#Preview("Folder drop - One and several") {
    DSPreviewPair {
        HStack {
            SidebarFolderDropFeedback(names: ["atlas"])
            SidebarFolderDropFeedback(names: ["atlas", "pier", "native"])
        }.frame(width: DS.Size.sidebarWidth * 2, height: 480)
    }
}
#endif
