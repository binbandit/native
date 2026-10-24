import CodeThemes
import NativePolicy
import SwiftUI

struct CodeThemeSettingsRow: View {
    static let rowID = SettingsRowID("appearance.code-theme")
    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID, title: "Code theme", description: "Colors for code blocks, diffs and the terminal.",
            keywords: ["syntax", "highlighting", "colors", "dracula", "nord", "solarized", "github", "catppuccin"])
    }

    @AppStorage private var light: String
    @AppStorage private var dark: String
    @AppStorage private var source: String
    @State private var selection: CodeThemeSelection
    @State private var specimen = SpecimenLine.sample()
    @State private var lock: CodeAppearance?
    @Environment(PluginRegistry.self) private var plugins
    @Environment(PolicyCenter.self) private var policyCenter: PolicyCenter?
    @Environment(AppModel.self) private var model: AppModel?
    @Environment(GitStore.self) private var git: GitStore?
    @Environment(SettingsPresentation.self) private var settings: SettingsPresentation?
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fixedSpecimen: SpecimenLine?
    var ghosttyColors = false

    init(
        defaults: UserDefaults = .standard, fixedSpecimen: SpecimenLine? = nil, ghosttyColors: Bool = false,
        initiallyShowsPolicyDetails: Bool = false
    ) {
        _light = AppStorage(wrappedValue: "native", AppearancePreferences.lightCodeThemeKey, store: defaults)
        _dark = AppStorage(wrappedValue: "native", AppearancePreferences.darkCodeThemeKey, store: defaults)
        _source = AppStorage(wrappedValue: "latest", AppearancePreferences.specimenKey, store: defaults)
        _lock = State(initialValue: initiallyShowsPolicyDetails ? .light : nil)
        _selection = State(initialValue: CodeThemeSelection(defaults: defaults))
        self.fixedSpecimen = fixedSpecimen
        self.ghosttyColors = ghosttyColors
    }

    private var policy: NativePolicy { policyCenter?.policy ?? PolicyCenter.shared.policy }
    private var catalog: PluginThemeCatalog { PluginThemeCatalog(plugins) }
    private var excerpt: SpecimenLine {
        source == "sample" ? .sample(language: specimen.language) : fixedSpecimen ?? specimen
    }
    private var themes: DSCodeThemes {
        DSCodeThemes(light: chosen(.light), dark: chosen(.dark))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Code theme").font(DS.Settings.groupTitle).accessibilityAddTraits(.isHeader)
                Spacer()
                Menu {
                    Toggle(
                        "Use Sample Code",
                        isOn: Binding(get: { source == "sample" }, set: { source = $0 ? "sample" : "latest" }))
                    if policy.appearanceCodeTheme == nil {
                        let current = chosen(scheme == .dark ? .dark : .light)
                        if current.light != nil && current.dark != nil {
                            Button("Use for Both Modes") {
                                selection.select(current.id.rawValue, for: nil, undoManager: undoManager)
                            }
                        }
                        Button("Reset to Native") { selection.select("native", for: nil, undoManager: undoManager) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .dsHitTarget(DS.Settings.controlHeight)
                .accessibilityLabel("Code theme options")
            }
            .foregroundStyle(.dsTextPrimary)
            VStack(spacing: 0) {
                CodeThemeCardWell(specimen: excerpt)
                    .dsCodeThemes(themes)
                    .animation(reduceMotion ? nil : .dsQuick, value: themes)
                themeRow(.dark)
                SeparatorLine().padding(.leading, DS.Settings.rowInset)
                themeRow(.light)
            }
            .background(.dsSurface)
            .clipShape(.rect(cornerRadius: DS.Radius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.panel).strokeBorder(
                    .dsSeparator, lineWidth: DS.Settings.hairline)
            }
            SettingsFooter(footer)
            if policy.appearanceCodeTheme == nil {
                unavailableChoice(dark)
                if light != dark { unavailableChoice(light) }
            }
        }
        .settingsRevealTarget(Self.rowID)
        .task {
            guard fixedSpecimen == nil, let model else { return }
            let result = await AppearanceSpecimenSource.load(model: model, git: git)
            if !Task.isCancelled { specimen = result }
        }
    }

    private func chosen(_ appearance: CodeAppearance) -> CodeTheme {
        let theme = catalog.codeTheme(id: policy.appearanceCodeTheme ?? (appearance == .dark ? dark : light)) ?? .native
        return theme.palette(for: appearance) == nil ? .native : theme
    }

    private func themeRow(_ appearance: CodeAppearance) -> some View {
        SettingsRow(appearance == .dark ? "Dark mode" : "Light mode") {
            if policy.appearanceCodeTheme != nil {
                Button {
                    lock = appearance
                } label: {
                    Label(chosen(appearance).name, systemImage: "lock.fill")
                        .font(.dsCallout)
                        .foregroundStyle(.dsTextSecondary)
                }
                .buttonStyle(.plain)
                .dsHitTarget(DS.Settings.controlHeight)
                .accessibilityLabel(
                    "\(appearance == .dark ? "Dark" : "Light") mode code theme, \(chosen(appearance).name), set by \(policy.organizationName ?? "your organization")"
                )
                .popover(isPresented: Binding(get: { lock == appearance }, set: { if !$0 { lock = nil } })) {
                    AppearancePolicyDetails(policy: policy)
                }
            } else {
                CodeThemeSelect(
                    appearance: appearance, selected: chosen(appearance),
                    entries: catalog.entries.filter { $0.theme.palette(for: appearance) != nil }
                ) { theme in
                    selection.select(theme.id.rawValue, for: appearance, undoManager: undoManager)
                }
            }
        }
        .padding(.horizontal, DS.Settings.rowInset)
        .padding(.vertical, DS.Settings.rowVerticalInset)
        .frame(minHeight: max(DS.Settings.rowHeight, DS.Size.minimumHitTarget))
    }

    private var footer: String {
        var text =
            policy.appearanceCodeTheme != nil
            ? "Both modes. The rest of this page is yours."
            : "Code blocks, diffs and the terminal use it. Try On shows each theme on your latest task, live."
        if ghosttyColors { text += " The terminal uses your Ghostty colors." }
        return text
    }

    @ViewBuilder private func unavailableChoice(_ id: String) -> some View {
        if catalog.codeTheme(id: id) == nil,
            let loaded = plugins.plugins.first(where: { loaded in
                PluginThemeCatalog.check(loaded.plugin.manifest).codeThemes.contains { $0.id.rawValue == id }
            }), plugins.isAllowed(loaded.id),
            let theme = PluginThemeCatalog.check(loaded.plugin.manifest).codeThemes.first(where: {
                $0.id.rawValue == id
            })
        {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SettingsFooter(
                    "\(theme.name) is from \(loaded.plugin.manifest.name), which is off. Native is in use until it's back."
                )
                Button("Turn On \(loaded.plugin.manifest.name)") {
                    settings?.open(.extensions, revealing: ExtensionsSettingsPage.rowID(loaded.id))
                }
                .buttonStyle(.settings)
                .padding(.leading, DS.Settings.rowInset)
            }
        }
    }
}

#if DEBUG
#Preview("Appearance - Latest change") {
    AppearancePreviewFixtures.card()
}
#Preview("Appearance - Sample source") {
    AppearancePreviewFixtures.card(sample: true)
}
#Preview("Appearance - Plugin and plugin off") {
    VStack {
        AppearancePreviewFixtures.card(plugin: true)
        AppearancePreviewFixtures.card(plugin: true, disabled: true)
    }
}
#Preview("Appearance - Locked code theme") {
    AppearancePreviewFixtures.card(locked: true)
}
#Preview("Appearance - Locked popover") {
    AppearancePreviewFixtures.card(locked: true, showLock: true)
}
#Preview("Appearance - Narrow code theme") {
    AppearancePreviewFixtures.card(width: 320)
}
#endif
