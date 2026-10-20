import SwiftUI

/// A branch name in mono on a sunken chip.
struct BranchChip: View {
    let name: String

    var body: some View {
        Label {
            Text(name)
                .font(.dsMonoCaption)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: DS.Size.navIcon - DS.Space.xxs))
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.dsTextPrimary)
        .padding(.horizontal, DS.Space.md)
        .frame(height: DS.Size.controlXS)
        .background(.dsSurfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .help(name)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Branch chip") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            BranchChip(name: "main")
            BranchChip(name: "native/queue-follow-ups")
            BranchChip(name: "dependabot/github_actions/actions/setup-node-7.1.0")
                .frame(width: 200, alignment: .leading)
        }
    }
}
#endif
