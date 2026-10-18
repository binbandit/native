import CodeThemes
import SwiftUI

/// Settings ▸ Appearance ▸ Code theme: the syntax colors for code blocks and diffs, chosen apart for
/// light and dark mode, each with a preview drawn in its own appearance (the reference app's code-theme row,
/// doubled).
struct CodeThemeSettingsRow: View {
    static let rowID = SettingsRowID("appearance.code-theme")

    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID,
            title: "Code theme",
            description: "Syntax colors for code blocks and diffs.",
            keywords: ["syntax", "highlighting", "colors", "dracula", "nord", "solarized", "github", "catppuccin"]
        )
    }

    @AppStorage(AppearancePreferences.lightCodeThemeKey) private var light = CodeTheme.native.id.rawValue
    @AppStorage(AppearancePreferences.darkCodeThemeKey) private var dark = CodeTheme.native.id.rawValue
    @Environment(PluginRegistry.self) private var plugins

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(
                id: Self.rowID,
                "Code theme",
                description: Text("Syntax colors for code blocks and diffs, one for light mode and one for dark.")
            ) {
                EmptyView()
            }
            HStack(alignment: .top, spacing: DS.Space.lg) {
                let themes = PluginThemeCatalog(plugins).allCodeThemes
                CodeThemePreview(appearance: .light, selection: $light, themes: themes)
                CodeThemePreview(appearance: .dark, selection: $dark, themes: themes)
            }
        }
    }
}

/// One appearance's choice: its picker, then a code block and a diff drawn in that theme.
private struct CodeThemePreview: View {
    let appearance: CodeAppearance
    @Binding var selection: String

    /// Built-in and plugin themes, labelled with their plugin's name.
    let themes: [CodeTheme]

    @Environment(\.dsCodeThemes) private var windowThemes

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text(appearance == .light ? "Light mode" : "Dark mode")
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextSecondary)
                Spacer(minLength: DS.Space.md)
                SettingsSelect(
                    label: appearance == .light ? "Light mode code theme" : "Dark mode code theme",
                    selection: $selection,
                    options: themes.filter { $0.palette(for: appearance) != nil }
                        .map { .init(value: $0.id.rawValue, title: $0.name) },
                    width: SettingsMetrics.selectWidth * 1.5
                )
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HighlightedCode(Self.sample, language: "ts")
                    .codeTextStyle()
                    .padding(DS.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.dsCodeBlockBackground, in: .rect(cornerRadius: DS.Radius.card))
                DiffView(path: "user.ts", oldText: Self.before, newText: Self.after)
            }
            .padding(DS.Space.md)
            .background(.dsBackground, in: .rect(cornerRadius: DS.Radius.panel))
            .overlay { RoundedRectangle(cornerRadius: DS.Radius.panel).strokeBorder(.dsSeparator, lineWidth: 1) }
            .environment(\.colorScheme, appearance == .light ? .light : .dark)
            .dsCodeThemes(previewThemes)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the \(appearance == .light ? "light" : "dark") mode code theme")
        }
        .frame(maxWidth: .infinity)
    }

    /// The window's themes with this appearance's choice in place, so the preview follows the picker.
    private var previewThemes: DSCodeThemes {
        var preview = windowThemes
        let theme = themes.first { $0.id.rawValue == selection } ?? .native
        if appearance == .light {
            preview.light = theme
        } else {
            preview.dark = theme
        }
        return preview
    }

    private static let sample = """
        // Fetch user data
        async function getUser(id: number): Promise<User> {
            const response = await fetch(`/api/users/${id}`);
            return { name: response.name, active: true };
        }
        """

    private static let before = "const limit = 10;\nexport default getUser;\n"
    private static let after = "const limit = 25; // per page\nexport default getUser;\n"
}
