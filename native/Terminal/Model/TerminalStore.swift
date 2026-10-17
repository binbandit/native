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

    @ObservationIgnored private var panels: [SessionKey: TerminalPanelModel] = [:]
    @ObservationIgnored private var engine: TerminalEngine?
    @ObservationIgnored private var didStartEngine = false
    /// The app's appearance and its terminal background, text and cursor, reported by the session
    /// view (`TerminalPanelModifier`) before any terminal starts.
    @ObservationIgnored private var appearance: (TerminalAppearance, TerminalChrome)?
    @ObservationIgnored private var appliedStyle: TerminalStyle?
    @ObservationIgnored private let makeEngine: @MainActor () -> Result<TerminalEngine, TerminalEngineError>

    /// - Parameter makeEngine: Starts the engine the first time a terminal opens.
    init(
        preferences: TerminalPreferences = TerminalPreferences(),
        makeEngine: @escaping @MainActor () -> Result<TerminalEngine, TerminalEngineError> = TerminalStore.platformEngine
    ) {
        self.preferences = preferences
        self.makeEngine = makeEngine
        #if canImport(GhosttyKit)
        availability = .available
        #else
        availability = .notBuilt
        #endif
        preferences.onChange = { [weak self] in self?.applyStyle() }
    }

    /// The task's panel, created hidden and empty the first time it's asked for.
    func panel(for session: SessionModel) -> TerminalPanelModel {
        let panel = panels[session.key] ?? makePanel(for: session)
        panel.focusComposer = { [weak session] in session?.wantsComposerFocus = true }
        return panel
    }

    /// ⌃`: shows and focuses the task's terminal; from the terminal, hides it and returns to the
    /// composer.
    func toggle(for session: SessionModel) {
        let panel = panel(for: session)
        if !panel.isVisible {
            panel.show()
        } else if panel.isFocused {
            panel.hide()
        } else {
            panel.focusSelected()
        }
    }

    /// ⌃⇧`: opens a new tab in the task's terminal and focuses it.
    func newTab(for session: SessionModel) {
        panel(for: session).newTab()
    }

    /// Ends a task's shells, for when the task is closed or archived.
    func closeTerminals(for key: SessionKey) {
        panels.removeValue(forKey: key)?.closeAll()
    }

    /// Records the app's appearance and restyles every terminal to match.
    func setAppearance(_ appearance: TerminalAppearance, chrome: TerminalChrome) {
        self.appearance = (appearance, chrome)
        applyStyle()
    }

    private func makePanel(for session: SessionModel) -> TerminalPanelModel {
        let panel = TerminalPanelModel(workingDirectory: session.cwd, command: Self.debugCommand) { [weak self] in
            self?.startedEngine()
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

    private func applyStyle() {
        guard let engine, let (appearance, chrome) = appearance else { return }
        let settings = preferences.settings
        let colors = TerminalTheme.named(settings.themeID).colors(for: appearance, appChrome: chrome)
        let style = TerminalStyle(settings: settings, appearance: appearance, colors: colors)
        guard style != appliedStyle else { return }
        appliedStyle = style
        engine.apply(style)
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
