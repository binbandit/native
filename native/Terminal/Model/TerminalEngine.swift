import Foundation
import Terminal

/// One tab's running terminal, as the engine drawing it exposes it. On the Mac it's a libghostty
/// surface (`GhosttySurfaceView`); the model never sees the platform view itself.
protocol TerminalSurface: AnyObject {
    /// Whether closing would interrupt something: a program other than the idle shell is running.
    var needsConfirmClose: Bool { get }
    var isFocused: Bool { get }
    /// Moves keyboard focus into the terminal, now or as soon as it's on screen.
    func focus()
    /// Sends ⌃C to the program running in the terminal, as pressing it would.
    func interrupt()
    /// Ends the shell and frees the terminal. The surface is unusable afterwards.
    func close()
}

/// What a surface tells its panel about itself.
protocol TerminalSurfaceEvents: AnyObject {
    func surface(_ id: UUID, didSetTitle title: String?)
    func surface(_ id: UUID, didChangeStatus status: TerminalStatus)
    /// Shell integration reports foreground work independently of the surface's visibility.
    func surface(_ id: UUID, didChangeCommandRunning isRunning: Bool)
    /// A command marked with OSC 133 ended with `status` (`133;D;<status>`). A job's frame reports
    /// its exit status this way, since the login wrapper hides the shell's own on the Mac.
    func surface(_ id: UUID, didFinishCommandWith status: Int32, after duration: Duration)
    /// The terminal asked to go away: its shell exited and the user pressed a key.
    func surfaceDidRequestClose(_ id: UUID)
    func surface(_ id: UUID, didChangeFocus isFocused: Bool)
    /// A key binding in the user's Ghostty config asked for something Native does with its tabs.
    func surface(_ id: UUID, didRequest request: TerminalSurfaceRequest)
}

/// What a terminal's key bindings can ask its panel to do.
enum TerminalSurfaceRequest: Equatable {
    case newTab
    /// Ghostty's `next_tab` and `previous_tab`.
    case selectTab(offset: Int)
    /// Ghostty's `goto_tab:N` (1-based) and `last_tab` (`Int.max`).
    case goToTab(number: Int)
    case reloadConfig
}

/// What a terminal starts with.
struct TerminalLaunch {
    /// The folder the shell starts in.
    var workingDirectory: URL
    /// A command to run instead of the user's login shell; nil runs the login shell.
    var command: String?
}

/// Makes and styles terminals. The Mac's engine is libghostty running the shell locally; a
/// host-backed engine (`docs/terminal.md`, "Remote and iPad") would attach to a pty the host owns.
protocol TerminalEngine: AnyObject {
    func makeSurface(
        id: UUID, launch: TerminalLaunch, events: TerminalSurfaceEvents
    ) throws(TerminalStartFailure)
        -> TerminalSurface
    /// Restyles every terminal, running ones included. With `ghostty`, the user's Ghostty config
    /// at those locations replaces `style`'s settings; the result says which applied.
    func apply(_ style: TerminalStyle, ghostty: GhosttyConfigLocations?) -> TerminalApplied
}

/// What restyling the terminals did.
struct TerminalApplied: Equatable {
    var status: TerminalConfigStatus
    /// The terminals' background opacity in effect (the user's Ghostty config can set it), so the
    /// panel puts a blur behind a translucent one.
    var backgroundOpacity: Double
}
