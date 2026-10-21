import Observation
import SessionTools

/// One session screen's tools: which is open in each place, and the state each tool keeps there.
@Observable
final class SessionToolsScreenModel {
    /// The open tool in each place; a place without one is closed.
    private(set) var openByPlace: [SessionToolPlace: SessionToolID] = [:]
    @ObservationIgnored private var states: [SessionToolID: AnyObject] = [:]
    @ObservationIgnored private let registry: SessionToolRegistry

    init(registry: SessionToolRegistry = .shared) {
        self.registry = registry
    }

    var openTools: Set<SessionToolID> {
        Set(openByPlace.values)
    }

    func isOpen(_ id: SessionToolID) -> Bool {
        openByPlace[registry.place(of: id)] == id
    }

    /// Opens the tool in its place, in place of whatever was open there. A tool that's off, or
    /// has no pane, doesn't open.
    func open(_ id: SessionToolID) {
        let place = registry.place(of: id)
        guard place != .off, registry.tool(id)?.pane != nil else { return }
        openByPlace[place] = id
    }

    func close(_ id: SessionToolID) {
        for (place, openID) in openByPlace where openID == id {
            openByPlace[place] = nil
        }
    }

    func close(_ place: SessionToolPlace) {
        openByPlace[place] = nil
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
