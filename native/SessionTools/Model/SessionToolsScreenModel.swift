import Observation
import SessionTools
import SwiftUI

/// One session screen's tools: which is open in each place, and the state each tool keeps there.
/// Commands, facts and the transcript all open tools through it.
@Observable
final class SessionToolsScreenModel {
    var hasWell = false
    var showsWell = false
    var wellPage: TaskWellTool?
    @ObservationIgnored var wellToolAvailable: (TaskWellTool) -> Bool = { _ in false }
    @ObservationIgnored var wellToolEnabled: (TaskWellTool) -> Bool = { _ in true }
    @ObservationIgnored var wellToolAction: (TaskWellTool) -> Void = { _ in }
    /// The title's popover, where the task is renamed (Task ▸ Rename Task… opens it too).
    var showsTitle = false
    /// Exports the branch as a patch, while the well offers that in place of the pull request.
    var wellExportPatch: (() -> Void)?

    func toggleWell() {
        wellPage = nil
        showsTitle = false
        showsWell.toggle()
    }

    func showTitle() {
        showsWell = false
        showsTitle = true
    }

    func showWellTools() {
        wellPage = nil
    }

    func performWellTool(_ tool: TaskWellTool) {
        guard hasWell, wellToolAvailable(tool), wellToolEnabled(tool) else { return }
        wellPage = tool == .dev || tool == .subagents ? tool : nil
        showsWell = wellPage != nil
        wellToolAction(tool)
    }

    /// The open tool in each place; a place without one is closed.
    private var presentation = SessionToolPresentation()
    /// A tool whose plugin was turned off is never open, even before `closeRemovedTools` runs.
    var openByPlace: [SessionToolPlace: SessionToolID] {
        presentation.openByPlace.filter { registry.tool($0.value) != nil }
    }
    /// Makes room in the window before the side panel appears, then shows it (`InspectorRoom`).
    @ObservationIgnored var makeRoomForSidePanel: (@escaping @MainActor () -> Void) -> Void = { $0() }
    @ObservationIgnored private var states: [SessionToolID: AnyObject] = [:]
    @ObservationIgnored private weak var session: SessionModel?
    @ObservationIgnored private var closeHooks: [SessionToolID: () -> Void] = [:]
    @ObservationIgnored let registry: SessionToolRegistry

    init(registry: SessionToolRegistry = .shared, session: SessionModel? = nil) {
        self.registry = registry
        self.session = session
    }

    var openTools: Set<SessionToolID> {
        Set(openByPlace.values)
    }

    func isOpen(_ id: SessionToolID) -> Bool {
        presentation.contains(id, at: registry.place(of: id))
    }

    /// Opens the tool in its place, in place of whatever was open there. A tool that's off, or has
    /// no pane, doesn't open.
    func open(_ id: SessionToolID) {
        guard let tool = registry.tool(id),
            let place = presentation.request(tool.spec, arrangement: registry.arrangement, hasPane: tool.pane != nil)
        else { return }
        showsWell = false
        // The side panel appears without sliding in, once there's room: sliding lays the whole
        // window out again every frame.
        let show: @MainActor @Sendable () -> Void = { [self] in
            // Its plugin may have been turned off while the window made room.
            guard self.registry.tool(id) != nil else { return self.close(id) }
            self.changePresentation { self.presentation.present(id, at: place) }
            if self.presentation.openByPlace[place] == id, self.closeHooks[id] == nil, let session = self.session {
                // Keep the original contribution after revocation, without retaining the screen through its hook.
                self.closeHooks[id] = { [weak self, weak session] in
                    guard let self, let session else { return }
                    tool.didClose(SessionToolContext(session: session, screen: self, tool: id))
                }
            }
        }
        if place == .side, openByPlace[.side] == nil {
            makeRoomForSidePanel(show)
        } else {
            show()
        }
    }

    /// Forgets panes whose tool is gone (its plugin turned off), so they come back closed.
    func closeRemovedTools() {
        for id in presentation.tools where registry.tool(id) == nil {
            close(id)
        }
    }

    func close(_ id: SessionToolID) {
        changePresentation { presentation.close(id) }
    }

    /// Closes without animation: closing the side panel animated, while the window settled its
    /// columns, sent AppKit into a constraint loop.
    func close(_ place: SessionToolPlace) {
        changePresentation { presentation.close(place) }
    }

    private func changePresentation(_ change: () -> Void) {
        let before = Set(presentation.openByPlace.values)
        withTransaction(\.disablesAnimations, true, change)
        for id in before.subtracting(presentation.openByPlace.values) {
            closeHooks.removeValue(forKey: id)?()
        }
    }

    func toggle(_ id: SessionToolID) {
        // The existing tool shortcuts take the same path as choosing a row in the well.
        showsWell = false
        if isOpen(id) { close(id) } else { open(id) }
    }

    func state<State: AnyObject>(for tool: SessionToolID, _ make: () -> State) -> State {
        if let state = states[tool] as? State { return state }
        let state = make()
        states[tool] = state
        return state
    }
}
