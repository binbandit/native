import SwiftUI

/// Under the code theme card after Try On's Keep: what changed, with Undo where it says so.
struct ThemeTryOnKeptLine: View {
    let message: String
    /// Theme names in `message`, set in the primary color.
    var names: [String] = []
    let undo: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "checkmark")
                .font(.dsBody)
                .foregroundStyle(.dsSuccess)
                .accessibilityHidden(true)
            Text(styledMessage)
                .font(DS.Settings.caption)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Undo", action: undo)
                .buttonStyle(.plain)
                .font(DS.Settings.caption)
                .foregroundStyle(.dsTextSecondary)
                .underline()
                .dsHitTarget(DS.Settings.controlHeight)
                .padding(.leading, DS.Space.xs)
        }
        .padding(.horizontal, DS.Settings.rowInset)
        .accessibilityElement(children: .combine)
    }

    private var styledMessage: AttributedString {
        var styled = AttributedString(message)
        for name in names {
            if let range = styled.range(of: name) { styled[range].foregroundColor = .dsTextPrimary }
        }
        return styled
    }
}

#if DEBUG
#Preview("Try On - Kept line") {
    DSPreviewPair {
        ThemeTryOnKeptLine(
            message: "Kept Tokyo Night for dark mode. The terminal uses it too.", names: ["Tokyo Night"]
        ) {}
        .frame(width: DS.Settings.pageWidth, alignment: .leading)
    }
}
#endif
