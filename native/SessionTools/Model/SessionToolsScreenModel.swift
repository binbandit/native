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
    var openByPlace: [SessionToolPlace: SessionToolID] { presentation.openByPlace }
    /// Makes room in the window before the side panel appears, then shows it (`InspectorRoom`).
    @ObservationIgnored var makeRoomForSidePanel: (@escaping @MainActor () -> Void) -> Void = { $0() }
    @ObservationIgnored private var states: [SessionToolID: AnyObject] = [:]
    @ObservationIgnored let registry: SessionToolRegistry

    init(registry: SessionToolRegistry = .shared) {
        self.registry = registry
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
        let show: @MainActor @Sendable () -> Void = {
            withTransaction(\.disablesAnimations, true) { self.presentation.present(id, at: place) }
        }
        if place == .side, openByPlace[.side] == nil {
            makeRoomForSidePanel(show)
        } else {
            show()
        }
    }

    func close(_ id: SessionToolID) {
        withTransaction(\.disablesAnimations, true) { presentation.close(id) }
    }

    /// Closes without animation: closing the side panel animated, while the window settled its
    /// columns, sent AppKit into a constraint loop.
    func close(_ place: SessionToolPlace) {
        withTransaction(\.disablesAnimations, true) { presentation.close(place) }
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
