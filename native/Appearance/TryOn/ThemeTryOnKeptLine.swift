import SwiftUI

/// Under the code theme card after Try On's Keep: what changed, with Undo where it says so.
struct ThemeTryOnKeptLine: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "checkmark")
                .font(.dsBody)
                .foregroundStyle(.dsSuccess)
                .accessibilityHidden(true)
            Text(message)
                .font(DS.Settings.caption)
                .foregroundStyle(.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Undo", action: undo)
                .buttonStyle(.plain)
                .font(DS.Settings.caption)
                .foregroundStyle(.dsTextSecondary)
                .dsHitTarget(DS.Settings.controlHeight)
                .padding(.leading, DS.Space.xs)
        }
        .padding(.horizontal, DS.Settings.rowInset)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Try On - Kept line") {
    DSPreviewPair {
        ThemeTryOnKeptLine(message: "Kept Tokyo Night for dark mode. The terminal uses it too.") {}
            .frame(width: DS.Settings.pageWidth, alignment: .leading)
    }
}
#endif
