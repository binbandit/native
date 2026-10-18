import Foundation
import Observation
import Terminal

/// One task's terminal panel: its tabs, each tab's running terminal, and whether it's showing.
/// Shells keep running while the panel is hidden or another task is selected; they end when their
/// tab closes.
@Observable
final class TerminalPanelModel: TerminalSurfaceEvents {
    /// The task's folder (its worktree, when it has one), where new tabs start.
    let workingDirectory: URL
    var isVisible = false
    private(set) var tabs = TerminalTabList()
    /// The tab the user asked to close while a program runs in it, awaiting confirmation.
    var confirmingClose: UUID?
    /// The tab whose terminal has keyboard focus.
    private(set) var focusedTab: UUID?

    var isFocused: Bool {
        focusedTab != nil
    }

    @ObservationIgnored private var surfaces: [UUID: TerminalSurface] = [:]
    @ObservationIgnored private let engine: () -> TerminalEngine?
    /// Hands focus back to the task's composer when the terminal gives it up.
    @ObservationIgnored var focusComposer: () -> Void = {}
    /// Rereads the user's Ghostty config (`reload_config` in their key bindings).
    @ObservationIgnored var reloadConfig: () -> Void = {}
    /// A command every tab runs instead of a shell (a sign-in, say); nil for the user's shell.
    @ObservationIgnored private let command: String?
    /// The command for a new shell: the user's chosen shell, or `shell` when given; nil leaves the
    /// choice to the terminal's config. Fails when the shell isn't there.
    @ObservationIgnored var resolveShell: (_ shell: String?) -> Result<String?, TerminalStartFailure> = { _ in
        .success(nil)
    }

    init(workingDirectory: URL, command: String? = nil, engine: @escaping () -> TerminalEngine?) {
        self.workingDirectory = workingDirectory
        self.command = command
        self.engine = engine
    }

    func surface(for id: UUID) -> TerminalSurface? {
        surfaces[id]
    }

    /// Shows the panel, opening a first tab if there's none, and focuses the selected terminal.
    func show() {
        isVisible = true
        if tabs.isEmpty {
            newTab()
        } else {
            focusSelected()
        }
    }

    /// Hides the panel; its shells keep running.
    func hide() {
        let hadFocus = isFocused
        isVisible = false
        if hadFocus {
            focusComposer()
        }
    }

    func newTab() {
        let tab = tabs.add()
        isVisible = true
        start(tab.id, in: workingDirectory)
        focusSelected()
    }

    func select(_ id: UUID) {
        tabs.select(id)
        focusSelected()
    }

    func selectTab(offset: Int) {
        tabs.selectTab(offset: offset)
        focusSelected()
    }

    /// Closes a tab, first asking when a program is still running in it.
    func requestClose(_ id: UUID) {
        if surfaces[id]?.needsConfirmClose == true {
            confirmingClose = id
        } else {
            close(id)
        }
    }

    func close(_ id: UUID) {
        let hadFocus = focusedTab == id
        if confirmingClose == id {
            confirmingClose = nil
        }
        surfaces.removeValue(forKey: id)?.close()
        tabs.close(id)
        if focusedTab == id {
            focusedTab = nil
        }
        if tabs.isEmpty {
            isVisible = false
            if hadFocus {
                focusComposer()
            }
        } else if hadFocus {
            focusSelected()
        }
    }

    /// Starts a fresh shell in a tab whose shell ended or never started, in `directory` or the
    /// task's folder.
    /// - Parameter shell: A shell to run this time instead of the chosen one, such as the
    ///   fallback when the chosen one is missing.
    func restart(_ id: UUID, in directory: URL? = nil, shell: String? = nil) {
        surfaces.removeValue(forKey: id)?.close()
        tabs.setTitle(nil, of: id)
        tabs.setStatus(.running, of: id)
        start(id, in: directory ?? workingDirectory, shell: shell)
        if tabs.selectedID == id {
            focusSelected()
        }
    }

    /// Ends every shell, for when the task goes away.
    func closeAll() {
        for id in tabs.tabs.map(\.id) {
            surfaces.removeValue(forKey: id)?.close()
            tabs.close(id)
        }
        isVisible = false
    }

    /// Whether the selected tab has a terminal that can take keyboard focus.
    var canFocus: Bool {
        tabs.selectedID.flatMap { surfaces[$0] } != nil
    }

    func focusSelected() {
        guard let id = tabs.selectedID else { return }
        surfaces[id]?.focus()
    }

    private func start(_ id: UUID, in directory: URL, shell: String? = nil) {
        guard let engine = engine() else {
            tabs.setStatus(.failedToStart(.engineFailed), of: id)
            return
        }
        do {
            let command = try command ?? resolveShell(shell).get()
            surfaces[id] = try engine.makeSurface(
                id: id, launch: TerminalLaunch(workingDirectory: directory, command: command), events: self)
        } catch let failure as TerminalStartFailure {
            tabs.setStatus(.failedToStart(failure), of: id)
        } catch {
            tabs.setStatus(.failedToStart(.engineFailed), of: id)
        }
    }

    // MARK: TerminalSurfaceEvents

    func surface(_ id: UUID, didSetTitle title: String?) {
        tabs.setTitle(title, of: id)
    }

    func surface(_ id: UUID, didChangeStatus status: TerminalStatus) {
        tabs.setStatus(status, of: id)
        if status != .running {
            // The last title is the command that ended the shell ("exit"); the tab's name reads better.
            tabs.setTitle(nil, of: id)
        }
    }

    func surfaceDidRequestClose(_ id: UUID) {
        close(id)
    }

    func surface(_ id: UUID, didRequest request: TerminalSurfaceRequest) {
        switch request {
        case .newTab:
            newTab()
        case .selectTab(offset: let offset):
            selectTab(offset: offset)
        case .goToTab(number: let number):
            let index = min(number, tabs.tabs.count) - 1
            if tabs.tabs.indices.contains(index) {
                select(tabs.tabs[index].id)
            }
        case .reloadConfig:
            reloadConfig()
        }
    }

    func surface(_ id: UUID, didChangeFocus isFocused: Bool) {
        if isFocused {
            focusedTab = id
        } else if focusedTab == id {
            focusedTab = nil
        }
    }
}
