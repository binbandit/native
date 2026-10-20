import SwiftUI

/// Settings ▸ Appearance ▸ Appearance: System, Light or Dark, the page's first choice, with a small
/// window drawn in each so the choice shows whatever the app looks like now.
struct AppearanceModeSettingsRow: View {
    static let rowID = SettingsRowID("appearance.mode")

    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID,
            title: "Appearance",
            description: "Light, dark, or match the system.",
            keywords: ["dark mode", "light mode", "night", "theme", "system", "automatic", "auto"]
        )
    }

    @Environment(AppearanceModeController.self) private var appearance

    var body: some View {
        @Bindable var appearance = appearance
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(id: Self.rowID, "Appearance", description: Text(Self.description)) {
                SettingsSelect(
                    label: "Appearance",
                    selection: $appearance.mode,
                    options: AppearanceMode.allCases.map { .init(value: $0, title: $0.title) }
                )
            }
            HStack(spacing: DS.Space.lg) {
                ForEach(AppearanceMode.allCases) { mode in
                    AppearanceChoiceTile(
                        title: mode.title, isSelected: mode == appearance.mode,
                        accessibilityLabel: "\(mode.title) appearance"
                    ) {
                        appearance.mode = mode
                    } preview: {
                        preview(mode)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func preview(_ mode: AppearanceMode) -> some View {
        switch mode.colorScheme {
        case .some(let scheme):
            AppearancePreviewWindow().environment(\.colorScheme, scheme)
        case .none:
            // Light and dark split on the diagonal, for following the system through both.
            AppearancePreviewWindow()
                .environment(\.colorScheme, .light)
                .overlay {
                    AppearancePreviewWindow()
                        .environment(\.colorScheme, .dark)
                        .mask(LowerTrailingHalf())
                }
        }
    }

    private static var description: String {
        #if os(macOS)
        "Light, dark, or match your Mac, switching when it does."
        #else
        "Light, dark, or match your iPad, switching when it does."
        #endif
    }
}

/// The triangle below the diagonal from the top trailing corner to the bottom leading one.
private nonisolated struct LowerTrailingHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Appearance mode row") {
    DSPreviewPair {
        SettingsRowGroup {
            AppearanceModeSettingsRow()
        }
        .settingsPreviewPage()
    }
    .environment(AppearanceModeController(defaults: PreviewUserDefaults()))
}
#endif
