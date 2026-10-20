import Observation
import SessionTools
import SwiftUI

/// One session screen's tools: which is open in each place, and the state each tool keeps there.
/// Commands, facts and the transcript all open tools through it.
@Observable
final class SessionToolsScreenModel {
    /// The open tool in each place; a place without one is closed.
    private(set) var openByPlace: [SessionToolPlace: SessionToolID] = [:]
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
        openByPlace[registry.place(of: id)] == id
    }

    /// Opens the tool in its place, in place of whatever was open there. A tool that's off, or has
    /// no pane, doesn't open.
    func open(_ id: SessionToolID) {
        let place = registry.place(of: id)
        guard place != .off, registry.tool(id)?.pane != nil else { return }
        // The side panel appears without sliding in, once there's room: sliding lays the whole
        // window out again every frame.
        let show: @MainActor @Sendable () -> Void = {
            withTransaction(\.disablesAnimations, true) { self.openByPlace[place] = id }
        }
        if place == .side, openByPlace[.side] == nil {
            makeRoomForSidePanel(show)
        } else {
            show()
        }
    }

    func close(_ id: SessionToolID) {
        for (place, openID) in openByPlace where openID == id {
            close(place)
        }
    }

    /// Closes without animation: closing the side panel animated, while the window settled its
    /// columns, sent AppKit into a constraint loop.
    func close(_ place: SessionToolPlace) {
        withTransaction(\.disablesAnimations, true) { openByPlace[place] = nil }
    }

    func toggle(_ id: SessionToolID) {
        if isOpen(id) { close(id) } else { open(id) }
    }

    func state<State: AnyObject>(for tool: SessionToolID, _ make: () -> State) -> State {
        if let state = states[tool] as? State { return state }
        let state = make()
        states[tool] = state
        return state
    }
}
