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
        case findingTask
        /// A read-only sample, when there's no task to show.
        case sample
    }

    /// The line Settings shows after Keep, with its Undo.
    struct KeptNote: Equatable {
        let message: String
        /// The kept themes' names in `message`, which the line sets apart.
        let names: [String]
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
    @ObservationIgnored private let loadSession: (SessionKey) async -> Void
    @ObservationIgnored private var taskSearch: Task<Void, Never>?

    init(
        app: AppModel, settings: SettingsPresentation, appearance: AppearanceModeController,
        plugins: PluginRegistry? = nil, defaults: UserDefaults = .standard,
        policy: @escaping () -> NativePolicy = { PolicyCenter.shared.policy },
        loadSession: ((SessionKey) async -> Void)? = nil
    ) {
        self.app = app
        self.plugins = plugins ?? app.plugins
        self.settings = settings
        self.appearance = appearance
        self.defaults = defaults
        self.policy = policy
        self.loadSession = loadSession ?? { await app.loadSession($0) }
    }

    /// Whether Try On can open: not while an organization sets the code theme, and not twice.
    var isAvailable: Bool { !isLockedByPolicy && !isActive }

    /// Whether an organization sets the code theme, which then wins over anything tried.
    var isLockedByPolicy: Bool { policy().appearanceCodeTheme != nil }

    /// The code themes the window shows while trying; nil when Try On isn't running, and as soon as
    /// an organization starts setting the code theme, so its theme shows before Try On has ended.
    var previewThemes: DSCodeThemes? {
        guard let trial, !isLockedByPolicy else { return nil }
        return DSCodeThemes(light: trial.shown(.light), dark: trial.shown(.dark))
    }

    /// Opens Try On on `task` (from the View menu), or on the latest task with code when nil (from
    /// Settings). Either way it opens the sample instead when that task shows no code to recolor,
    /// since arrowing through themes there would change nothing visible.
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
        settings.close()
        trial = Trial(
            kept: kept, mode: scheme, light: Self.themes(.light, in: catalog), dark: Self.themes(.dark, in: catalog))
        if let task {
            showTask(app.session(task).map(Self.showsCode) == true ? task : nil)
        } else if app.sessionList.isEmpty {
            showTask(nil)
        } else {
            stage = .findingTask
            taskSearch = Task { [weak self] in
                guard let self else { return }
                let task = await latestTask()
                guard !Task.isCancelled, isActive else { return }
                guard !isLockedByPolicy else { return policyChanged() }
                showTask(task)
                taskSearch = nil
            }
        }
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
        guard !isLockedByPolicy else { return policyChanged() }
        guard let trial, let choice = trial.writes(.keep) else { return }
        guard trial.hasChanges else { return finish() }
        let message = Self.message(for: trial)
        apply(choice, undoing: trial.kept, undoManager: undoManager)
        let returnsToSettings = origin?.settingsPane != nil
        finish()
        if let message {
            keptNote =
                returnsToSettings
                ? KeptNote(
                    message: message, names: Self.changedModes(in: trial).map { trial.shown($0).name },
                    before: trial.kept, after: choice) : nil
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

    /// An organization started setting the code theme mid-trial: there's nothing left to try, so Try
    /// On ends as Cancel does, writing nothing.
    func policyChanged() {
        guard isActive, isLockedByPolicy else { return }
        finish()
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
        taskSearch?.cancel()
        taskSearch = nil
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

    private func showTask(_ key: SessionKey?) {
        stage = key.map(Stage.task) ?? .sample
        if let key { app.selection = key }
    }

    /// Completed tasks load lazily after relaunch. Inspect the catalog in activity order, loading
    /// history through the normal model path, so an older open task doesn't hide a newer candidate.
    private func latestTask() async -> SessionKey? {
        let candidates = app.sessionList
            .map { (key: $0.id, activity: app.lastActivity(for: $0) ?? .distantPast) }
            .sorted { $0.activity > $1.activity }
        for candidate in candidates {
            guard !Task.isCancelled, !isLockedByPolicy else { return nil }
            if app.session(candidate.key) == nil { await loadSession(candidate.key) }
            guard !Task.isCancelled else { return nil }
            guard let session = app.session(candidate.key), session.parentID == nil, session.origin == .user
            else { continue }
            // Hosts answer an attached open before replay finishes. Its first chunks cannot tell
            // us whether the task has code; already-loading models need the same wait.
            for await phase in Observations({ session.phase }) where phase != .loading { break }
            guard !Task.isCancelled else { return nil }
            if Self.showsCode(session) { return candidate.key }
        }
        return nil
    }

    /// Whether the task shows code the themes recolor: captured changes, a diff in a tool call, or a
    /// code block in a reply.
    private static func showsCode(_ session: SessionModel) -> Bool {
        guard GitChangesReview.previewDiffs(of: session).isEmpty else { return true }
        return session.state.items.contains { item in
            switch item {
            case .message(let message): message.role == .agent && message.text.contains("```")
            case .toolCall(let call): call.content.contains { if case .diff = $0 { true } else { false } }
            default: false
            }
        }
    }

    private static func themes(_ appearance: CodeAppearance, in catalog: PluginThemeCatalog) -> [CodeTheme] {
        catalog.allCodeThemes.filter { $0.palette(for: appearance) != nil }
    }

    private func announce() {
        guard let trial else { return }
        AccessibilityNotification.Announcement("Previewing \(trial.highlighted.name)").post()
    }

    /// The modes whose theme Keep changes, the listed one first.
    private static func changedModes(in trial: Trial) -> [CodeAppearance] {
        [trial.mode, trial.mode == .dark ? .light : .dark].filter { trial.shown($0) != trial.inUse($0) }
    }

    /// "Kept Tokyo Night for dark mode. The terminal uses it too.", naming the listed mode first; nil
    /// when nothing changed.
    static func message(for trial: Trial) -> String? {
        let modes = changedModes(in: trial)
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
