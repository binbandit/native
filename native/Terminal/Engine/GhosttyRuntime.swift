#if canImport(GhosttyKit)
import AppKit
import GhosttyKit
import OSLog
import Terminal

/// The process's one libghostty app, shared by every terminal. libghostty runs each shell on a
/// pty it owns, parses its output on its own threads and draws with Metal; this class feeds it
/// configuration, ticks it when it asks, and routes its callbacks to the surface they're for.
///
/// libghostty's embedding API (`ghostty.h`) is what Ghostty's own macOS app uses; it isn't
/// declared stable, so Native pins the commit it builds (`scripts/build-libghostty.sh`).
final class GhosttyRuntime: TerminalEngine {
    static let logger = Logger(subsystem: "Native", category: "Terminal")

    /// The started runtime, for libghostty's callbacks, which carry no context of ours.
    private(set) static var shared: GhosttyRuntime?

    private let app: ghostty_app_t
    private var style: TerminalStyle
    private let surfaces = NSHashTable<GhosttySurfaceView>.weakObjects()
    private var observers: [NSObjectProtocol] = []
    private var activityMonitor: Task<Void, Never>?

    /// Starts libghostty once per process; later calls return the same runtime.
    static func start() -> Result<GhosttyRuntime, TerminalEngineError> {
        if let shared {
            return .success(shared)
        }
        GhosttyConfigBuilder.prepareResources()
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            return .failure(.failed("libghostty couldn't initialize."))
        }
        guard let runtime = GhosttyRuntime() else {
            return .failure(.failed("libghostty couldn't create its terminal app."))
        }
        shared = runtime
        return .success(runtime)
    }

    private init?() {
        let appearance: TerminalAppearance =
            NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        let chrome = TerminalChrome.designSystem(
            appearance: appearance, palette: .original, lightTone: .paper, darkTone: .standard)
        // A starting point; `TerminalStore` applies the user's settings right after the app starts.
        style = TerminalStyle(
            settings: TerminalSettings(), appearance: appearance, appTheme: .native, appChrome: chrome)
        guard let built = GhosttyConfigBuilder.build(style, ghostty: nil) else { return nil }
        let config = built.config
        defer { ghostty_config_free(config) }

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = nil
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { _ in GhosttyRuntime.wakeUp() }
        runtime.action_cb = { _, target, action in GhosttyRuntime.perform(action, target: target) }
        runtime.read_clipboard_cb = { userdata, location, state, mimes, count, _ in
            GhosttyClipboard.read(surface: userdata, location: location, state: state, mimes: mimes, count: count)
        }
        runtime.confirm_read_clipboard_cb = { userdata, confirm, state, request in
            GhosttyClipboard.confirmRead(surface: userdata, confirm: confirm, state: state, request: request)
        }
        runtime.write_clipboard_cb = { _, location, contents, count, _ in
            GhosttyClipboard.write(location: location, contents: contents, count: count)
        }
        runtime.close_surface_cb = { userdata, _ in GhosttyRuntime.closeSurface(userdata) }
        guard let app = ghostty_app_new(&runtime, config) else { return nil }
        self.app = app
        ghostty_app_set_color_scheme(app, Self.colorScheme(appearance))
        ghostty_app_set_focus(app, NSApp.isActive)
        observeApp()
    }

    // MARK: TerminalEngine

    func makeSurface(
        id: UUID, launch: TerminalLaunch, events: TerminalSurfaceEvents
    ) throws(TerminalStartFailure)
        -> TerminalSurface
    {
        var isDirectory: ObjCBool = false
        let path = launch.workingDirectory.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .directoryMissing
        }
        guard
            let view = GhosttySurfaceView(
                app: app, id: id, launch: launch, events: events, colorScheme: Self.colorScheme(style.appearance))
        else {
            throw .engineFailed
        }
        surfaces.add(view)
        monitorActivity()
        return view
    }

    func apply(_ style: TerminalStyle, ghostty: GhosttyConfigLocations?) -> TerminalApplied {
        guard let built = GhosttyConfigBuilder.build(style, ghostty: ghostty) else {
            return TerminalApplied(status: .native, backgroundOpacity: 1)
        }
        defer { ghostty_config_free(built.config) }
        self.style = style
        // Updates the app's config and every running terminal's.
        ghostty_app_update_config(app, built.config)
        let scheme = Self.colorScheme(style.appearance)
        ghostty_app_set_color_scheme(app, scheme)
        for surface in surfaces.allObjects {
            surface.setColorScheme(scheme)
        }
        return TerminalApplied(status: built.status, backgroundOpacity: built.backgroundOpacity)
    }

    private func tick() {
        ghostty_app_tick(app)
        reportActivity()
    }

    @discardableResult
    private func reportActivity() -> Bool {
        let live = surfaces.allObjects.filter { $0.surface != nil }
        for surface in live { surface.reportCommandActivity() }
        return !live.isEmpty
    }

    private func monitorActivity() {
        guard activityMonitor == nil else { return }
        // Quiet programs and hidden panels still need activity updates. One monitor serves every
        // surface, stops after the last closes, and publishes only changes.
        activityMonitor = Task { [weak self] in
            while let self {
                guard reportActivity() else {
                    activityMonitor = nil
                    return
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private static func colorScheme(_ appearance: TerminalAppearance) -> ghostty_color_scheme_e {
        appearance == .dark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
    }

    private func observeApp() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { GhosttyRuntime.shared?.setFocus(true) }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { GhosttyRuntime.shared?.setFocus(false) }
            },
            center.addObserver(
                forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { GhosttyRuntime.shared?.keyboardDidChange() }
            },
        ]
    }

    private func setFocus(_ focused: Bool) {
        ghostty_app_set_focus(app, focused)
    }

    /// The input source changed; libghostty reloads its keyboard layout.
    private func keyboardDidChange() {
        ghostty_app_keyboard_changed(app)
    }

    // MARK: Callbacks

    /// libghostty has work to do; it may call from any thread.
    private nonisolated static func wakeUp() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { shared?.tick() }
        }
    }

    /// An action libghostty performs on the app or a surface; true when Native handled it.
    /// Actions arrive on the main thread, from inside `ghostty_app_tick` or a surface call.
    private nonisolated static func perform(_ action: ghostty_action_s, target: ghostty_target_s) -> Bool {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated {
            guard target.tag == GHOSTTY_TARGET_SURFACE, let view = GhosttySurfaceView.from(target.target.surface) else {
                return false
            }
            return view.perform(action)
        }
    }

    private nonisolated static func closeSurface(_ userdata: UnsafeMutableRawPointer?) {
        guard Thread.isMainThread else { return }
        nonisolated(unsafe) let userdata = userdata
        MainActor.assumeIsolated {
            GhosttySurfaceView.from(userdata: userdata)?.requestClose()
        }
    }
}
#endif
