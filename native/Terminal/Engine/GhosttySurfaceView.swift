#if canImport(GhosttyKit)
import AppKit
import GhosttyKit
import OSLog
import Terminal

/// One terminal: the AppKit view libghostty draws a surface into, and the surface itself. Created
/// by `GhosttyRuntime.makeSurface` and owned by its tab in `TerminalPanelModel`; SwiftUI only
/// hosts it (`TerminalSurfaceHost`), so it survives the panel hiding and tasks switching.
///
/// libghostty makes the view layer-hosting (an `IOSurfaceLayer` it renders into on its own
/// thread), spawns the shell on a pty, and turns the key, mouse and text events forwarded here
/// into terminal input. Input handling follows Ghostty's own macOS app (`SurfaceView_AppKit`).
final class GhosttySurfaceView: NSView, TerminalSurface {
    let id: UUID
    private(set) var surface: ghostty_surface_t?
    private weak var events: TerminalSurfaceEvents?
    private(set) var isFocused = false
    /// Focus asked for before the view was in a window.
    private var wantsFocus = false
    /// One cell's size in points, for placing the input method's candidate window.
    var cellSize = CGSize(width: 8, height: 16)
    private var cursorStyle: NSCursor = .iBeam
    /// Watches the window this view is in for being minimized, hidden or covered.
    private var occlusionObserver: (any NSObjectProtocol)?

    // Keyboard state, used by `GhosttySurfaceView+Keyboard`.
    var markedText = NSMutableAttributedString()
    /// Text the input method commits during one `keyDown`; nil outside one.
    var keyTextAccumulator: [String]?
    /// See `performKeyEquivalent(with:)`.
    var lastPerformKeyEvent: TimeInterval?

    init?(
        app: ghostty_app_t, id: UUID, launch: TerminalLaunch, events: TerminalSurfaceEvents,
        colorScheme: ghostty_color_scheme_e
    ) {
        self.id = id
        self.events = events
        // Non-zero, so the renderer has something to draw into before the first layout.
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque()))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        // Keep the last output on screen when the shell exits; Native shows what happened.
        config.wait_after_command = true
        let created = launch.workingDirectory.path(percentEncoded: false).withCString { directory in
            config.working_directory = directory
            guard let command = launch.command else {
                return ghostty_surface_new(app, &config)
            }
            return command.withCString { command in
                config.command = command
                return ghostty_surface_new(app, &config)
            }
        }
        guard let created else { return nil }
        surface = created
        ghostty_surface_set_color_scheme(created, colorScheme)
        updateTrackingAreas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    isolated deinit {
        occlusionObserver.map(NotificationCenter.default.removeObserver)
        if let surface {
            ghostty_surface_free(surface)
        }
    }

    /// The view a libghostty surface handle belongs to, from the userdata it was created with.
    static func from(_ surface: ghostty_surface_t?) -> GhosttySurfaceView? {
        guard let surface else { return nil }
        return from(userdata: ghostty_surface_userdata(surface))
    }

    static func from(userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    // MARK: TerminalSurface

    var needsConfirmClose: Bool {
        surface.map(ghostty_surface_needs_confirm_quit) ?? false
    }

    func reportCommandActivity() {
        guard let surface else { return }
        let running = !ghostty_surface_process_exited(surface) && ghostty_surface_needs_confirm_quit(surface)
        events?.surface(id, didChangeCommandRunning: running)
    }

    func focus() {
        if let window {
            window.makeFirstResponder(self)
        } else {
            wantsFocus = true
        }
    }

    func interrupt() {
        // Written to the pty as typed, unlike `ghostty_surface_text`, which pastes.
        perform(binding: #"text:\x03"#)
    }

    func close() {
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
        removeFromSuperview()
    }

    func setColorScheme(_ scheme: ghostty_color_scheme_e) {
        guard let surface else { return }
        ghostty_surface_set_color_scheme(surface, scheme)
    }

    func requestClose() {
        events?.surfaceDidRequestClose(id)
    }

    // MARK: Actions from libghostty

    /// Handles an action targeted at this surface; true when Native handled it.
    func perform(_ action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            let title = action.action.set_title.title.map { String(cString: $0) }
            events?.surface(id, didSetTitle: title)
            return true
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            let runtime = Duration.milliseconds(Int64(clamping: action.action.child_exited.timetime_ms))
            events?.surface(id, didChangeStatus: TerminalStatus(exitedAfter: runtime))
            return true
        case GHOSTTY_ACTION_COMMAND_FINISHED:
            let finished = action.action.command_finished
            events?.surface(
                id, didFinishCommandWith: Int32(finished.exit_code),
                after: .nanoseconds(Int64(clamping: finished.duration)))
            return true
        case GHOSTTY_ACTION_CLOSE_WINDOW, GHOSTTY_ACTION_CLOSE_TAB:
            requestClose()
            return true
        // Key bindings from the user's Ghostty config that map onto Native's terminal tabs.
        case GHOSTTY_ACTION_NEW_TAB:
            events?.surface(id, didRequest: .newTab)
            return true
        case GHOSTTY_ACTION_GOTO_TAB:
            let target = action.action.goto_tab
            let request: TerminalSurfaceRequest =
                switch target {
                case GHOSTTY_GOTO_TAB_PREVIOUS: .selectTab(offset: -1)
                case GHOSTTY_GOTO_TAB_NEXT: .selectTab(offset: 1)
                case GHOSTTY_GOTO_TAB_LAST: .goToTab(number: .max)
                default: .goToTab(number: Int(target.rawValue))
                }
            events?.surface(id, didRequest: request)
            return true
        case GHOSTTY_ACTION_RELOAD_CONFIG:
            events?.surface(id, didRequest: .reloadConfig)
            return true
        case GHOSTTY_ACTION_CELL_SIZE:
            let size = action.action.cell_size
            let scale = window?.backingScaleFactor ?? 2
            cellSize = CGSize(width: Double(size.width) / scale, height: Double(size.height) / scale)
            return true
        case GHOSTTY_ACTION_MOUSE_SHAPE:
            setCursor(for: action.action.mouse_shape)
            return true
        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            NSCursor.setHiddenUntilMouseMoves(action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN)
            return true
        case GHOSTTY_ACTION_OPEN_URL:
            return open(action.action.open_url)
        case GHOSTTY_ACTION_RENDERER_HEALTH:
            if action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_UNHEALTHY {
                GhosttyRuntime.logger.error("A terminal's renderer reported it's unhealthy.")
            }
            return true
        default:
            return false
        }
    }

    /// ⌘-click on a URL or path. Links a program printed (OSC 8) only open on the web.
    private func open(_ request: ghostty_action_open_url_s) -> Bool {
        guard let pointer = request.url else { return false }
        let data = Data(bytes: pointer, count: Int(request.len))
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let url: URL
        if let candidate = URL(string: text), let scheme = candidate.scheme {
            if request.kind == GHOSTTY_ACTION_OPEN_URL_KIND_OSC8, !["http", "https"].contains(scheme.lowercased()) {
                return false
            }
            url = candidate
        } else {
            guard request.kind != GHOSTTY_ACTION_OPEN_URL_KIND_OSC8 else { return false }
            url = URL(filePath: NSString(string: text).expandingTildeInPath)
        }
        NSWorkspace.shared.open(url)
        return true
    }

    private func setCursor(for shape: ghostty_action_mouse_shape_e) {
        cursorStyle =
            switch shape {
            case GHOSTTY_MOUSE_SHAPE_DEFAULT: .arrow
            case GHOSTTY_MOUSE_SHAPE_POINTER: .pointingHand
            case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: .crosshair
            case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED: .operationNotAllowed
            case GHOSTTY_MOUSE_SHAPE_GRAB: .openHand
            case GHOSTTY_MOUSE_SHAPE_GRABBING: .closedHand
            case GHOSTTY_MOUSE_SHAPE_EW_RESIZE, GHOSTTY_MOUSE_SHAPE_COL_RESIZE: .resizeLeftRight
            case GHOSTTY_MOUSE_SHAPE_NS_RESIZE, GHOSTTY_MOUSE_SHAPE_ROW_RESIZE: .resizeUpDown
            case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU: .contextualMenu
            default: .iBeam
            }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursorStyle)
    }

    // MARK: Focus

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            setFocused(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            setFocused(false)
        }
        return resigned
    }

    private func setFocused(_ focused: Bool) {
        guard isFocused != focused else { return }
        isFocused = focused
        if let surface {
            ghostty_surface_set_focus(surface, focused)
        }
        events?.surface(id, didChangeFocus: focused)
    }

    // MARK: Window, size and scale

    /// Off screen (panel hidden, another task selected, the window minimized, hidden or fully
    /// covered) the renderer stops drawing, and the cursor stops blinking.
    private func observeOcclusion() {
        occlusionObserver.map(NotificationCenter.default.removeObserver)
        occlusionObserver = window.map { window in
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateOcclusion() }
            }
        }
        updateOcclusion()
    }

    private func updateOcclusion() {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, window?.occlusionState.contains(.visible) == true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard surface != nil else { return }
        observeOcclusion()
        if window == nil {
            setFocused(false)
            return
        }
        updateDisplay()
        viewDidChangeBackingProperties()
        if wantsFocus {
            wantsFocus = false
            window?.makeFirstResponder(self)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            // libghostty scales its own drawing; stop Core Animation from scaling it again.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        let backing = convertToBacking(bounds)
        ghostty_surface_set_content_scale(surface, backing.width / bounds.width, backing.height / bounds.height)
        updateSurfaceSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        let backing = convertToBacking(bounds.size)
        ghostty_surface_set_size(surface, UInt32(backing.width.rounded()), UInt32(backing.height.rounded()))
    }

    /// The display drives libghostty's frame timing (its display link).
    private func updateDisplay() {
        guard let surface,
            let number = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return }
        ghostty_surface_set_display_id(surface, number.uint32Value)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
                owner: self
            ))
        super.updateTrackingAreas()
    }

    // MARK: Edit menu

    /// Runs one of libghostty's binding actions, such as `copy_to_clipboard`.
    @discardableResult
    func perform(binding action: String) -> Bool {
        guard let surface else { return false }
        return ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    @objc func copy(_ sender: Any?) {
        perform(binding: "copy_to_clipboard")
    }

    @objc func paste(_ sender: Any?) {
        perform(binding: "paste_from_clipboard")
    }

    override func selectAll(_ sender: Any?) {
        perform(binding: "select_all")
    }

    @objc func clearTerminal(_ sender: Any?) {
        perform(binding: "clear_screen")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Clear", action: #selector(clearTerminal(_:)), keyEquivalent: "")
        return menu
    }
}

extension GhosttySurfaceView: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)):
            surface.map(ghostty_surface_has_selection) ?? false
        case #selector(paste(_:)):
            NSPasteboard.general.string(forType: .string) != nil
        default:
            surface != nil
        }
    }
}
#endif
