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
    /// Ends the shell and frees the terminal. The surface is unusable afterwards.
    func close()
}

/// What a surface tells its panel about itself.
protocol TerminalSurfaceEvents: AnyObject {
    func surface(_ id: UUID, didSetTitle title: String?)
    func surface(_ id: UUID, didChangeStatus status: TerminalStatus)
    /// The terminal asked to go away: its shell exited and the user pressed a key.
    func surfaceDidRequestClose(_ id: UUID)
    func surface(_ id: UUID, didChangeFocus isFocused: Bool)
}

/// What a terminal starts with.
struct TerminalLaunch {
    /// The folder the shell starts in.
    var workingDirectory: URL
    /// A command to run instead of the user's login shell (`/bin/sh -c`); nil runs the login shell.
    var command: String?
}

/// Makes terminals. The Mac's is libghostty running the shell locally; a host-backed engine
/// (`docs/terminal.md`, "Remote and iPad") would attach to a pty the host owns instead.
protocol TerminalEngine: AnyObject {
    func makeSurface(id: UUID, launch: TerminalLaunch, events: TerminalSurfaceEvents) -> TerminalSurface?
}
