import SwiftUI

/// A link under a New Tasks group to where its values are edited, in the footer's size.
struct NewTasksFooterLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                Text(title)
                Image(systemName: "chevron.right").font(.dsMicro)
            }
            .font(DS.Settings.caption)
            .foregroundStyle(.dsTextPrimary)
        }
        .buttonStyle(.plain)
        .dsHitTarget(DS.Settings.controlHeight)
    }
}

#if DEBUG
#Preview("New Tasks - Footer link") {
    DSPreviewPair {
        NewTasksFooterLink(title: "Edit modes in Modes") {}.padding(DS.Space.lg)
    }
}
#endif
