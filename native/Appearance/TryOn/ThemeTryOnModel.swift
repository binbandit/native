import ACP
import CodeThemes
import NativePolicy
import Observation
import SwiftUI

/// The light and dark backgrounds, tried on with the code themes.
nonisolated struct ThemeTryOnBackgrounds: Equatable, Sendable {
    var light: DSLightTone
    var dark: DSDarkTone
}

/// Try On Themes: previews code themes and backgrounds on a real task in the main window, with the
/// sidebar as the theme list, until the user keeps one or cancels. It opens from Settings ▸
/// Appearance (on the latest task with changes) or View ▸ Appearance (on the task in view), and
/// returns there afterwards. Nothing is written before Keep, and it never changes a task: agents
/// keep running, and the task is only shown.
@MainActor
@Observable
final class ThemeTryOnModel {
    typealias Trial = ThemeTrial<ThemeTryOnBackgrounds>

    /// What Try On shows the themes on.
    enum Stage: Equatable {
        case task(SessionKey)
        /// A read-only sample, when there's no task to show.
        case sample
    }

    /// The line Settings shows after Keep, with its Undo.
    struct KeptNote: Equatable {
        let message: String
        fileprivate let before: Trial.Choice
        fileprivate let after: Trial.Choice
    }

    /// Where Try On returns on Keep or Cancel.
    private struct Origin {
        let settingsPane: SettingsPane.ID?
        let selection: SessionKey?
        /// The scheme the window had, so the list's other mode can show without being saved.
        let scheme: CodeAppearance
    }

    private(set) var trial: Trial?
    private(set) var stage: Stage?
    private(set) var keptNote: KeptNote?

    var isActive: Bool { trial != nil }

    @ObservationIgnored private var origin: Origin?
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let plugins: PluginRegistry
    @ObservationIgnored private let settings: SettingsPresentation
    @ObservationIgnored private let appearance: AppearanceModeController
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let policy: () -> NativePolicy

    init(
        app: AppModel, settings: SettingsPresentation, appearance: AppearanceModeController,
        plugins: PluginRegistry? = nil, defaults: UserDefaults = .standard,
        policy: @escaping () -> NativePolicy = { PolicyCenter.shared.policy }
    ) {
        self.app = app
        self.plugins = plugins ?? app.plugins
        self.settings = settings
        self.appearance = appearance
        self.defaults = defaults
        self.policy = policy
    }

    /// Whether Try On can open: not while an organization sets the code theme, and not twice.
    var isAvailable: Bool { policy().appearanceCodeTheme == nil && !isActive }

    /// Opens Try On on `task`, or on the latest task with changes when nil (from Settings), or on
    /// the sample when there's no task at all.
    func start(on task: SessionKey? = nil) {
        guard isAvailable else { return }
        let scheme: CodeAppearance = appearance.effectiveScheme == .dark ? .dark : .light
        origin = Origin(settingsPane: settings.pane, selection: app.selection, scheme: scheme)
        let catalog = PluginThemeCatalog(plugins)
        let kept = Trial.Choice(
            light: CodeTheme.ID(rawValue: stored(AppearancePreferences.lightCodeThemeKey)),
            dark: CodeTheme.ID(rawValue: stored(AppearancePreferences.darkCodeThemeKey)),
            backgrounds: storedBackgrounds)
        keptNote = nil
        let stage = task.map(Stage.task) ?? latestTask().map(Stage.task) ?? .sample
        settings.close()
        if case .task(let key) = stage { app.selection = key }
        self.stage = stage
        trial = Trial(
            kept: kept, mode: scheme, light: Self.themes(.light, in: catalog), dark: Self.themes(.dark, in: catalog))
    }

    // MARK: Trying

    func highlight(_ id: CodeTheme.ID) {
        trial?.highlight(id)
        announce()
    }

    func move(_ offset: Int) {
        trial?.move(offset)
        announce()
    }

    @discardableResult
    func highlight(matching prefix: String) -> Bool {
        guard trial?.highlight(matching: prefix) == true else { return false }
        announce()
        return true
    }

    /// Lists `mode`'s themes, and shows the window in that mode while it isn't the one it had.
    func show(_ mode: CodeAppearance) {
        guard var trial, trial.mode != mode else { return }
        trial.mode = mode
        self.trial = trial
        appearance.preview(mode == origin?.scheme ? nil : mode == .dark ? .dark : .light)
        announce()
    }

    func setBackgrounds(_ backgrounds: ThemeTryOnBackgrounds) {
        trial?.setBackgrounds(backgrounds)
    }

    /// Plugins changed while trying: their themes come and go from the list.
    func reloadThemes() {
        let catalog = PluginThemeCatalog(plugins)
        trial?.update(light: Self.themes(.light, in: catalog), dark: Self.themes(.dark, in: catalog))
    }

    // MARK: Ending

    /// Writes both modes' themes and the backgrounds, and returns to where Try On opened.
    func keep(undoManager: UndoManager?) {
        guard let trial, let choice = trial.writes(.keep) else { return }
        guard trial.hasChanges else { return finish() }
        let message = Self.message(for: trial)
        apply(choice, undoing: trial.kept, undoManager: undoManager)
        let returnsToSettings = origin?.settingsPane != nil
        finish()
        if let message {
            keptNote = returnsToSettings ? KeptNote(message: message, before: trial.kept, after: choice) : nil
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// Writes nothing and returns to where Try On opened.
    func cancel() {
        guard isActive else { return }
        finish()
    }

    /// Ends Try On to open `task` instead (a task that needs the user), writing nothing.
    func open(_ task: SessionKey) {
        end()
        app.selection = task
    }

    /// Ends Try On where the user went instead (Settings, another task), writing nothing.
    func abandon() {
        guard isActive else { return }
        end()
    }

    /// The Undo at the end of Settings' kept line.
    func undoKeep(undoManager: UndoManager?) {
        guard let keptNote else { return }
        undoManager?.removeAllActions(withTarget: self)
        write(keptNote.before)
        self.keptNote = nil
    }

    /// Settings' kept line goes once the user leaves the page.
    func dismissKeptNote() {
        keptNote = nil
    }

    private func finish() {
        guard let origin else { return end() }
        end()
        if app.selection != origin.selection { app.selection = origin.selection }
        if let pane = origin.settingsPane { settings.open(pane, revealing: CodeThemeSettingsRow.rowID) }
    }

    private func end() {
        trial = nil
        stage = nil
        origin = nil
        appearance.preview(nil)
    }

    private func apply(_ choice: Trial.Choice, undoing before: Trial.Choice, undoManager: UndoManager?) {
        write(choice)
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.keptNote = nil
                target.apply(before, undoing: choice, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Code Theme")
    }

    private func write(_ choice: Trial.Choice) {
        if policy().appearanceCodeTheme == nil {
            defaults.set(choice.light.rawValue, forKey: AppearancePreferences.lightCodeThemeKey)
            defaults.set(choice.dark.rawValue, forKey: AppearancePreferences.darkCodeThemeKey)
        }
        defaults.set(choice.backgrounds.light.rawValue, forKey: AppearancePreferences.lightToneKey)
        defaults.set(choice.backgrounds.dark.rawValue, forKey: AppearancePreferences.darkToneKey)
    }

    // MARK: Reading

    private func stored(_ key: String) -> String { defaults.string(forKey: key) ?? CodeTheme.native.id.rawValue }

    private var storedBackgrounds: ThemeTryOnBackgrounds {
        ThemeTryOnBackgrounds(
            light: defaults.string(forKey: AppearancePreferences.lightToneKey).flatMap(DSLightTone.init) ?? .paper,
            dark: defaults.string(forKey: AppearancePreferences.darkToneKey).flatMap(DSDarkTone.init) ?? .standard)
    }

    /// The task whose turn ended last with changes, else the one used last; never a running one.
    private func latestTask() -> SessionKey? {
        let tasks = app.sessions.loadedSessions
            .filter { $0.parentID == nil && $0.origin == .user && $0.phase != .loading }
            .sorted {
                ($0.state.turns.last?.endedAt ?? $0.lastActivity ?? .distantPast)
                    > ($1.state.turns.last?.endedAt ?? $1.lastActivity ?? .distantPast)
            }
        return (tasks.first { !GitChangesReview.previewDiffs(of: $0).isEmpty } ?? tasks.first)?.key
    }

    private static func themes(_ appearance: CodeAppearance, in catalog: PluginThemeCatalog) -> [CodeTheme] {
        catalog.allCodeThemes.filter { $0.palette(for: appearance) != nil }
    }

    private func announce() {
        guard let trial else { return }
        AccessibilityNotification.Announcement("Previewing \(trial.highlighted.name)").post()
    }

    /// "Kept Tokyo Night for dark mode. The terminal uses it too.", naming the listed mode first; nil
    /// when nothing changed.
    static func message(for trial: Trial) -> String? {
        let modes = [trial.mode, trial.mode == .dark ? .light : .dark].filter {
            trial.shown($0) != trial.inUse($0)
        }
        let kept = modes.map { "\(trial.shown($0).name) for \($0 == .dark ? "dark" : "light") mode" }
        if !kept.isEmpty {
            return "Kept \(kept.joined(separator: " and ")). The terminal uses \(kept.count == 1 ? "it" : "them") too."
        }
        let tried = trial.tried.backgrounds
        let before = trial.kept.backgrounds
        let backgrounds = [
            tried.light != before.light ? "the \(tried.light.title) light background" : nil,
            tried.dark != before.dark ? "the \(tried.dark.title) dark background" : nil,
        ].compactMap(\.self)
        return backgrounds.isEmpty ? nil : "Kept \(backgrounds.joined(separator: " and "))."
    }
}
