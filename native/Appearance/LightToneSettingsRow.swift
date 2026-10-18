import SwiftUI

/// Settings ▸ Appearance ▸ Light mode: Paper or Wool, the white light mode is drawn on, with a
/// small light-mode window in each so the choice shows even while the app is dark.
struct LightToneSettingsRow: View {
    static let rowID = SettingsRowID("appearance.light-tone")

    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID,
            title: "Light mode",
            description: "Draw light mode on crisp Paper white or warm Wool.",
            keywords: ["paper", "wool", "white", "off-white", "warm", "cream", "background", "glare"]
        )
    }

    @AppStorage(AppearancePreferences.lightToneKey) private var lightTone = DSLightTone.paper

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(
                id: Self.rowID,
                "Light mode",
                description: Text("Draw light mode on crisp Paper white, or on Wool, a warm off-white that’s easier on the eyes.")
            ) {
                SettingsSelect(
                    label: "Light mode",
                    selection: $lightTone,
                    options: DSLightTone.allCases.map { .init(value: $0, title: $0.title) }
                )
            }
            HStack(spacing: DS.Space.lg) {
                ForEach(DSLightTone.allCases) { tone in
                    LightToneTile(tone: tone, isSelected: tone == lightTone) {
                        lightTone = tone
                    }
                }
            }
        }
    }
}

/// One tone's choice: a small light-mode window drawn in that tone, and its name.
private struct LightToneTile: View {
    let tone: DSLightTone
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
        Button(action: select) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                window
                    .frame(height: Metrics.height)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
                    .environment(\.colorScheme, .light)
                    .dsLightTone(tone)
                    .padding(Metrics.ring)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.panel + Metrics.ring, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.dsAccent : isHovered ? .dsBorderHover : .clear,
                                lineWidth: Metrics.ringWidth)
                    }
                HStack(spacing: DS.Space.xs) {
                    Text(tone.title)
                        .settingsText(.bodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.dsAccent)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, Metrics.ring)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .accessibilityLabel("\(tone.title) light mode")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A sidebar beside a transcript with a code block and the composer, in light mode.
    private var window: some View {
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
                    .padding(DS.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.row))
                Spacer(minLength: 0)
                Text("Ask for a change…")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
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
        static let height: CGFloat = 132
        static let sidebarWidth: CGFloat = 112
        static let rowHeight: CGFloat = 20
        /// The selection ring sits this far outside the window, Conductor's theme-card ring.
        static let ring: CGFloat = 3
        static let ringWidth: CGFloat = 2
    }
}
