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
