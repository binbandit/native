import CodeThemes
import SwiftUI

struct CodeThemeSelect: View {
    let appearance: CodeAppearance
    let selected: CodeTheme
    let entries: [PluginThemeCatalog.Entry]
    let select: (CodeTheme) -> Void
    @Environment(\.dsLightTone) private var lightTone
    @Environment(\.dsDarkTone) private var darkTone
    @Environment(\.displayScale) private var scale

    private var title: String { appearance == .dark ? "Dark mode" : "Light mode" }
    private var pluginNames: [String] {
        entries.compactMap(\.pluginName).reduce(into: []) { result, name in
            if !result.contains(name) { result.append(name) }
        }
    }

    var body: some View {
        Menu {
            Picker(
                title,
                selection: Binding(
                    get: { selected.id },
                    set: { id in
                        if let entry = entries.first(where: { $0.theme.id == id }) { select(entry.theme) }
                    })
            ) {
                ForEach(entries.filter { $0.pluginName == nil }) { entry in
                    option(entry.theme).tag(entry.id)
                }
                ForEach(pluginNames, id: \.self) { name in
                    Section(name) {
                        ForEach(entries.filter { $0.pluginName == name }) { entry in
                            option(entry.theme).tag(entry.id)
                        }
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: DS.Space.md) {
                CodeThemeChip(theme: selected, appearance: appearance)
                Text(selected.name)
                    .font(.dsCallout)
                    .foregroundStyle(selected.id == CodeTheme.native.id ? Color.dsTextSecondary : .dsTextPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
            }
            .frame(minHeight: DS.Settings.controlHeight)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .dsHitTarget(DS.Settings.controlHeight)
        .settingsFocusShape(RoundedRectangle(cornerRadius: DS.Radius.row))
        .accessibilityLabel("\(title) code theme")
        .accessibilityValue(selected.name)
    }

    private func option(_ theme: CodeTheme) -> some View {
        Label {
            Text(theme.name)
        } icon: {
            // Native menus accept images, not arbitrary SwiftUI stacks in their image column.
            let renderer = ImageRenderer(
                content: CodeThemeChip(theme: theme, appearance: appearance)
                    .dsLightTone(lightTone).dsDarkTone(darkTone))
            let image = menuImage(renderer)
            if let image { image.renderingMode(.original) }
        }
    }

    private func menuImage(_ renderer: ImageRenderer<some View>) -> Image? {
        renderer.scale = scale
        return renderer.cgImage.map { Image(decorative: $0, scale: scale) }
    }
}

#if DEBUG
#Preview("Appearance - Theme menu") {
    DSPreviewPair {
        CodeThemeSelect(
            appearance: .dark, selected: .native,
            entries: CodeTheme.all.filter { $0.dark != nil }.map { .init(theme: $0, pluginName: nil) }, select: { _ in }
        )
    }
}
#endif
