import Foundation
import Observation
import Terminal

/// Every task's terminal panel, and the engine that runs them. Panels are created on first use and
/// outlive their views, so switching tasks never restarts a shell.
@Observable
final class TerminalStore {
    let preferences: TerminalPreferences
    /// Whether this build can run terminals; `.failed` once the engine refused to start.
    private(set) var availability: TerminalAvailability
    /// Where the terminals' settings come from: Native's, or the user's Ghostty config.
    private(set) var configStatus: TerminalConfigStatus = .native
    /// The terminals' background opacity in effect; below 1 the panel blurs what's behind it.
    private(set) var backgroundOpacity: Double = 1
    /// The settings an import from Ghostty replaced, for Undo; cleared once settings change again.
    private(set) var settingsBeforeImport: TerminalSettings?
    /// The app's terminal colors: Native's, or the code theme's terminal palette, which the
    /// code-theme setting sets here. Colors imported from Ghostty and "Use my Ghostty settings"
    /// both take precedence over it.
    var appTheme: TerminalTheme = .native {
        didSet { applyStyle() }
    }

    @ObservationIgnored private var panels: [SessionKey: TerminalPanelModel] = [:]
    @ObservationIgnored private var engine: TerminalEngine?
    @ObservationIgnored private var didStartEngine = false
    /// The app's appearance and its terminal background, text and cursor, reported by the session
    /// screen (`SessionTerminalCompanion`) before any terminal starts.
    @ObservationIgnored private var appearance: (TerminalAppearance, TerminalChrome, TerminalTransparency)?
    @ObservationIgnored private var appliedStyle: TerminalStyle?
    @ObservationIgnored private let makeEngine: @MainActor () -> Result<TerminalEngine, TerminalEngineError>
    @ObservationIgnored private lazy var watcher = TerminalConfigWatcher { [weak self] in
        self?.reloadGhosttyConfig()
    }

    /// - Parameter makeEngine: Starts the engine the first time a terminal opens.
    init(
        preferences: TerminalPreferences = TerminalPreferences(),
        makeEngine: @escaping @MainActor () -> Result<TerminalEngine, TerminalEngineError> = TerminalStore
            .platformEngine
    ) {
        self.preferences = preferences
        self.makeEngine = makeEngine
        #if canImport(GhosttyKit)
        availability = .available
        #else
        availability = .notBuilt
        #endif
        preferences.onChange = { [weak self] in
            self?.settingsBeforeImport = nil
            self?.applyStyle()
        }
    }

    /// The task's panel, created hidden and empty the first time it's asked for.
    func panel(for session: SessionModel) -> TerminalPanelModel {
        let panel = panels[session.key] ?? makePanel(for: session)
        panel.focusComposer = { [weak session] in session?.wantsComposerFocus = true }
        return panel
    }

    /// ⌃`: shows and focuses the task's terminal; from the terminal, or when there's no terminal
    /// to focus, hides it and returns to the composer.
    func toggle(for session: SessionModel) {
        let panel = panel(for: session)
        if !panel.isVisible {
            panel.show()
        } else if panel.isFocused || !panel.canFocus {
            panel.hide()
            session.wantsComposerFocus = true
        } else {
            panel.focusSelected()
        }
    }

    /// ⌃⇧`: opens a new tab in the task's terminal and focuses it.
    func newTab(for session: SessionModel) {
        panel(for: session).newTab()
    }

    /// Runs a job in the task's terminal, in a tab of its own (`TerminalPanelModel.run(_:)`).
    @discardableResult
    func run(_ request: TerminalJobRequest, for session: SessionModel) -> UUID {
        panel(for: session).run(request)
    }

    /// The shell a job runs its command with: the one Settings ▸ Terminal chose, or
    /// `TerminalShell.fallback` when that one isn't there.
    var jobShell: String {
        let path = preferences.settings.shell.path(loginShell: TerminalLoginShell.current)
        return TerminalLoginShell.isRunnable(path) ? path : TerminalShell.fallback
    }

    /// Told when a job ends in any task's terminal, with the task and the job as it ended.
    @ObservationIgnored var jobFinished: (SessionKey, TerminalJob) -> Void = { _, _ in }

    /// A panel outside any task, running `command` instead of a login shell, for one-off jobs
    /// such as signing in to an agent. It isn't kept: the caller ends it with `closeAll()`.
    func standalonePanel(running command: String, in directory: URL) -> TerminalPanelModel {
        TerminalPanelModel(workingDirectory: directory, command: command) { [weak self] in
            self?.startedEngine()
        }
    }

    /// Ends a task's shells, for when the task is closed or archived.
    func closeTerminals(for key: SessionKey) {
        panels.removeValue(forKey: key)?.closeAll()
    }

    /// Records the app's appearance, keeping the transparency already reported, and restyles every
    /// terminal to match.
    func setAppearance(_ appearance: TerminalAppearance, chrome: TerminalChrome) {
        setAppearance(appearance, chrome: chrome, transparency: self.appearance?.2 ?? .opaque)
    }

    /// Records the app's appearance and transparency and restyles every terminal to match.
    func setAppearance(_ appearance: TerminalAppearance, chrome: TerminalChrome, transparency: TerminalTransparency) {
        self.appearance = (appearance, chrome, transparency)
        applyStyle()
    }

    /// Rereads the user's Ghostty config and restyles every terminal with it.
    func reloadGhosttyConfig() {
        applyStyle(force: true)
    }

    // MARK: Ghostty config

    /// The user's Ghostty config as a one-time import into Native's settings.
    func readGhosttyImport() -> TerminalImport {
        let locations = GhosttyConfigLocations.current
        let files = GhosttyConfigFile.load(locations, home: .homeDirectory)
        return GhosttyImporter.read(files, locations: locations) { urls in
            urls.lazy.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.first
        }
    }

    /// Copies an import into Native's settings, remembering the old ones for Undo.
    func applyImport(_ ghosttyImport: TerminalImport) {
        let previous = preferences.settings
        preferences.settings = ghosttyImport.applied(to: previous)
        settingsBeforeImport = previous
    }

    func undoImport() {
        guard let previous = settingsBeforeImport else { return }
        preferences.settings = previous
    }

    private func makePanel(for session: SessionModel) -> TerminalPanelModel {
        let panel = TerminalPanelModel(workingDirectory: session.cwd) { [weak self] in
            self?.startedEngine()
        }
        panel.reloadConfig = { [weak self] in self?.reloadGhosttyConfig() }
        let key = session.key
        panel.jobFinished = { [weak self] job in self?.jobFinished(key, job) }
        panel.resolveShell = { [weak self] shell in
            self?.shellCommand(override: shell) ?? .success(nil)
        }
        panels[session.key] = panel
        return panel
    }

    private func startedEngine() -> TerminalEngine? {
        if !didStartEngine {
            didStartEngine = true
            switch makeEngine() {
            case .success(let engine):
                self.engine = engine
                applyStyle()
            case .failure(.notBuilt):
                availability = .notBuilt
            case .failure(.failed(let reason)):
                availability = .failed(reason)
            }
        }
        return engine
    }

    private func applyStyle(force: Bool = false) {
        guard let (appearance, chrome, transparency) = appearance else { return }
        let settings = preferences.settings
        // Ghostty settings start the engine even before a terminal opens, so Settings can say
        // whether the user's config loads.
        let wantsEngine = settings.usesGhosttyConfig && availability == .available
        guard let engine = engine ?? (wantsEngine ? startedEngine() : nil) else {
            configStatus = settings.usesGhosttyConfig ? .ghosttyPending : .native
            return
        }
        let style = TerminalStyle(
            settings: settings, appearance: appearance, appTheme: appTheme, appChrome: chrome,
            transparency: transparency)
        guard force || style != appliedStyle else { return }
        appliedStyle = style
        let locations = settings.usesGhosttyConfig ? GhosttyConfigLocations.current : nil
        let applied = engine.apply(style, ghostty: locations)
        configStatus = applied.status
        backgroundOpacity = applied.backgroundOpacity
        if let locations {
            // The config, its includes, and the user's themes, so edits apply as they're saved.
            watcher.watch(configStatus.files + locations.defaultFiles + [locations.userThemes])
        } else {
            watcher.stop()
        }
    }

    /// The command a new shell tab runs: `override`, or the shell from Settings (the login shell
    /// by default), launched as a login shell. Nil when the user's Ghostty config, in use, sets its
    /// own `command`; a debug command when one was given.
    private func shellCommand(override: String?) -> Result<String?, TerminalStartFailure> {
        if override == nil, let debugCommand = Self.debugCommand {
            return .success(debugCommand)
        }
        let settings = preferences.settings
        if override == nil, settings.usesGhosttyConfig, case .ghostty = configStatus,
            let command = GhosttyConfigFile.load(.current, home: .homeDirectory).lastValue("command"), !command.isEmpty
        {
            return .success(nil)
        }
        let path = override ?? settings.shell.path(loginShell: TerminalLoginShell.current)
        guard TerminalLoginShell.isRunnable(path) else {
            return .failure(.shellNotFound(path))
        }
        return .success(TerminalShell.command(for: path))
    }

    /// A command to run instead of the login shell, for trying failure states by hand:
    /// `open -n Native.app --args -NativeTerminalCommand /nonexistent`.
    private static var debugCommand: String? {
        UserDefaults.standard.string(forKey: "NativeTerminalCommand")
    }

    /// libghostty on the Mac, when the build includes it.
    static func platformEngine() -> Result<TerminalEngine, TerminalEngineError> {
        #if canImport(GhosttyKit)
        GhosttyRuntime.start().map { $0 as TerminalEngine }
        #else
        .failure(.notBuilt)
        #endif
    }
}

/// Why the terminal engine didn't start.
enum TerminalEngineError: Error {
    case notBuilt
    case failed(String)
}
