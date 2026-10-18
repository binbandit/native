import SwiftUI

/// A small Native window for Settings ▸ Appearance's choices: a sidebar beside a transcript with a
/// code block and the composer, drawn in whatever color scheme and light tone its environment has,
/// so each choice shows itself whatever the app looks like now.
struct AppearancePreviewWindow: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                row("New Session")
                row("Sidebar polish", isSelected: true)
                row("Fix flaky test")
            }
            .padding(DS.Space.sm)
            .frame(width: Metrics.sidebarWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.dsSidebarSolid)
            SeparatorLine(axis: .vertical)
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("Moved the rows onto the shared fills.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextPrimary)
                Text("let tone = DSLightTone.wool")
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .padding(DS.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.row))
                Spacer(minLength: 0)
                Text("Ask for a change…")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .padding(DS.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(.dsBorder, lineWidth: 1)
                    }
            }
            .padding(DS.Space.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.dsBackground)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .accessibilityHidden(true)
    }

    private func row(_ title: String, isSelected: Bool = false) -> some View {
        Text(title)
            .font(.dsBody)
            .foregroundStyle(.dsTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.sm)
            .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight, alignment: .leading)
            .background(isSelected ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.row))
    }

    private enum Metrics {
        static let sidebarWidth: CGFloat = 112
        static let rowHeight: CGFloat = 20
    }
}
