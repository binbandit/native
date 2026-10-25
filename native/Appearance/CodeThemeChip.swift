import CodeThemes
import SwiftUI

struct CodeThemeChip: View {
    let theme: CodeTheme
    let appearance: CodeAppearance
    @Environment(\.dsLightTone) private var lightTone
    @Environment(\.dsDarkTone) private var darkTone

    var body: some View {
        let environment = EnvironmentValues.code(
            colorScheme: appearance == .dark ? .dark : .light, lightTone: lightTone, darkTone: darkTone,
            themes: DSCodeThemes(light: theme, dark: theme))
        let colors = DSCodeColors(environment, on: .sunken)
        HStack(spacing: DS.Appearance.tickGap) {
            ForEach([CodeTokenRole.keyword, .string, .function, .type], id: \.self) { role in
                RoundedRectangle(cornerRadius: DS.Appearance.tickRadius)
                    .fill(colors.color(role))
                    .frame(width: DS.Appearance.tickWidth, height: DS.Appearance.tickHeight)
            }
        }
        .frame(width: DS.Appearance.chipWidth, height: DS.Appearance.chipHeight)
        .background(
            Color(DSCodeBackground(surface: .sunken).resolve(in: environment)),
            in: .rect(cornerRadius: DS.Appearance.chipRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Appearance.chipRadius)
                .strokeBorder(.dsCodeWellEdge, lineWidth: DS.Settings.hairline)
        }
        .environment(\.colorScheme, appearance == .dark ? .dark : .light)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Appearance - Theme chips") {
    DSPreviewPair {
        VStack { ForEach(CodeTheme.all) { CodeThemeChip(theme: $0, appearance: .dark) } }
    }
}
#endif
