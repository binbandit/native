import CodeThemes
import SwiftUI

/// Try On's theme list, in the sidebar's column while Try On runs. The highlighted theme is what
/// the window shows; "In use" marks what the user has.
///
/// Keys (docs/keyboard.md), with focus in the list where it starts: ↑ and ↓ highlight and apply,
/// ← and → switch between Dark mode and Light mode, typing selects by name, Return keeps and
/// Escape cancels. Escape and ⌘. cancel from anywhere in the window (`windowCancelKeys`); on iPad,
/// these shortcuts are how.
struct ThemeTryOnPanel: View {
    let tryOn: ThemeTryOnModel
    @Environment(AppModel.self) private var app
    @Environment(PluginRegistry.self) private var plugins
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isListFocused: Bool
    @State private var typeSelect = ThemeTryOnTypeSelect()

    var body: some View {
        if let trial = tryOn.trial {
            VStack(alignment: .leading, spacing: 0) {
                header
                controls(trial)
                SeparatorLine().padding(.top, DS.TryOn.sectionGap)
                ThemeTryOnNeedsYouStrip(tasks: waitingTasks) { tryOn.open($0) }
                list(trial)
                SeparatorLine()
                footer(trial)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { isListFocused = true }
            .onChange(of: plugins.enabledPlugins.map(\.manifest)) { tryOn.reloadThemes() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Try On Themes")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.TryOn.subtitleGap) {
            HStack(spacing: DS.Space.md) {
                Text("Try On Themes")
                    .font(.dsCalloutMedium)
                    .foregroundStyle(.dsTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: tryOn.cancel) { Kbd("esc") }
                    .buttonStyle(.plain)
                    .dsHitTarget(DS.Size.controlXS)
                    .accessibilityHidden(true)
            }
            Text("On this task. Escape puts yours back.")
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.top, DS.Space.xs)
        .padding(.leading, DS.TryOn.headerLeading)
        .padding(.trailing, DS.Space.xl)
    }

    private func controls(_ trial: ThemeTryOnModel.Trial) -> some View {
        VStack(alignment: .leading, spacing: DS.TryOn.controlGap) {
            Picker(
                "Mode",
                selection: Binding(get: { trial.mode }, set: { mode in animated { tryOn.show(mode) } })
            ) {
                Label("Dark mode", systemImage: "moon").tag(CodeAppearance.dark)
                Label("Light mode", systemImage: "sun.max").tag(CodeAppearance.light)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Segments share the column's width rather than hugging their titles.
            .buttonSizing(.flexible)
            .frame(minWidth: 0, maxWidth: .infinity)
            // The label sits beside the switch, or above it when a longer background name or a
            // narrower column leaves no room.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.sm) {
                    backgroundLabel.frame(maxWidth: .infinity, alignment: .leading)
                    backgroundPicker(trial)
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    backgroundLabel
                    backgroundPicker(trial)
                }
            }
        }
        .padding(.top, DS.TryOn.sectionGap)
        .padding(.horizontal, DS.TryOn.controlInset)
    }

    private var backgroundLabel: some View {
        Text("Background")
            .font(.dsBody)
            .foregroundStyle(.dsTextTertiary)
            .lineLimit(1)
            .fixedSize()
    }

    private func backgroundPicker(_ trial: ThemeTryOnModel.Trial) -> some View {
        backgroundSegments(trial)
            .controlSize(.small)
            .fixedSize()
    }

    @ViewBuilder
    private func backgroundSegments(_ trial: ThemeTryOnModel.Trial) -> some View {
        let backgrounds = trial.tried.backgrounds
        if trial.mode == .dark {
            Picker(
                "Dark background",
                selection: Binding(
                    get: { backgrounds.dark },
                    set: { tone in animated { tryOn.setBackgrounds(.init(light: backgrounds.light, dark: tone)) } })
            ) {
                ForEach(DSDarkTone.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } else {
            Picker(
                "Light background",
                selection: Binding(
                    get: { backgrounds.light },
                    set: { tone in animated { tryOn.setBackgrounds(.init(light: tone, dark: backgrounds.dark)) } })
            ) {
                ForEach(DSLightTone.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func list(_ trial: ThemeTryOnModel.Trial) -> some View {
        let catalog = PluginThemeCatalog(plugins)
        let themes = trial.themes
        let builtIn = themes.filter { catalog.pluginNames[$0.id] == nil }
        let pluginNames = themes.compactMap { catalog.pluginNames[$0.id] }.reduce(into: [String]()) { names, name in
            if !names.contains(name) { names.append(name) }
        }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(builtIn) { row($0, in: trial) }
                    ForEach(pluginNames, id: \.self) { name in
                        ThemeTryOnPluginHeader(name: name)
                        ForEach(themes.filter { catalog.pluginNames[$0.id] == name }) { row($0, in: trial) }
                    }
                }
                .padding(.vertical, DS.Space.md)
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { handled { tryOn.move(-1) } }
            .onKeyPress(.downArrow) { handled { tryOn.move(1) } }
            .onKeyPress(.home) { handled { tryOn.move(-themes.count) } }
            .onKeyPress(.end) { handled { tryOn.move(themes.count) } }
            .onKeyPress(.leftArrow) { handled { tryOn.show(.dark) } }
            .onKeyPress(.rightArrow) { handled { tryOn.show(.light) } }
            .onKeyPress(.return) {
                tryOn.keep(undoManager: undoManager)
                return .handled
            }
            .onKeyPress(.escape) {
                tryOn.cancel()
                return .handled
            }
            .onKeyPress(characters: .alphanumerics.union(.whitespaces), phases: .down) { press in
                guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
                let prefix = typeSelect.append(press.characters)
                return animatedResult { tryOn.highlight(matching: prefix) } ? .handled : .ignored
            }
            .onChange(of: trial.highlighted.id) { _, id in
                withAnimation(reduceMotion ? nil : .dsQuick) { proxy.scrollTo(id) }
            }
            .accessibilityLabel(trial.mode == .dark ? "Code themes for dark mode" : "Code themes for light mode")
        }
    }

    private func row(_ theme: CodeTheme, in trial: ThemeTryOnModel.Trial) -> some View {
        ThemeTryOnRow(
            theme: theme, appearance: trial.mode, isHighlighted: theme == trial.highlighted,
            isInUse: theme == trial.inUse(trial.mode)
        ) {
            isListFocused = true
            animated { tryOn.highlight(theme.id) }
        }
        .id(theme.id)
    }

    private func footer(_ trial: ThemeTryOnModel.Trial) -> some View {
        HStack(spacing: DS.Space.md) {
            Button("Cancel", action: tryOn.cancel)
                .buttonStyle(.ds(.secondary, size: .medium))
                .keyboardShortcut(.cancelAction)
            Button {
                tryOn.keep(undoManager: undoManager)
            } label: {
                Text("Keep \(trial.highlighted.name)")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.ds(.primary, size: .medium))
        }
        // ⌘. cancels too; a button takes one shortcut, so this one is invisible.
        .background {
            Button("Cancel", action: tryOn.cancel)
                .keyboardShortcut(".", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.TryOn.footerBottom)
        .padding(.horizontal, DS.TryOn.controlInset)
    }

    /// Tasks waiting on the user, counted as the Dock badge counts them.
    private var waitingTasks: [SessionModel] {
        var seen = Set<SessionKey>()
        return app.sessionList.compactMap { summary in
            guard seen.insert(summary.id).inserted, let session = app.session(summary.id), session.needsApproval
            else { return nil }
            return session
        }
    }

    /// Recolors with `.dsQuick`, or at once under Reduce Motion.
    private func animated(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .dsQuick, change)
    }

    private func animatedResult(_ change: () -> Bool) -> Bool {
        withAnimation(reduceMotion ? nil : .dsQuick, change)
    }

    private func handled(_ change: () -> Void) -> KeyPress.Result {
        animated(change)
        return .handled
    }
}

/// Letters typed in quick succession select by name prefix ("to" for Tokyo Night).
private struct ThemeTryOnTypeSelect {
    private var prefix = ""
    private var last = Date.distantPast

    mutating func append(_ characters: String, at now: Date = .now) -> String {
        if now.timeIntervalSince(last) > 1 { prefix = "" }
        last = now
        prefix += characters
        return prefix
    }
}

private struct ThemeTryOnPluginHeader: View {
    let name: String

    var body: some View {
        HStack(spacing: 0) {
            Text("From \(name)").font(.dsCaptionMedium).foregroundStyle(.dsTextTertiary)
            Text(" · plugin").font(.dsCaption).foregroundStyle(.dsTextQuaternary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(name), plugin")
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.Space.xs)
        .padding(.leading, DS.TryOn.headerLeading)
        .accessibilityAddTraits(.isHeader)
    }
}
