/// The tools requested and shown on one screen. Opening may wait for the window to make room;
/// closing or choosing another tool during that wait must invalidate the earlier request.
public struct SessionToolPresentation: Equatable, Sendable {
    public private(set) var openByPlace: [SessionToolPlace: SessionToolID] = [:]
    private var pending: [SessionToolPlace: SessionToolID] = [:]

    public init() {}

    /// Every tool shown or still waiting to be, so ones that went away can be closed.
    public var tools: Set<SessionToolID> {
        Set(pending.values).union(openByPlace.values)
    }

    public func contains(_ id: SessionToolID, at place: SessionToolPlace) -> Bool {
        pending[place] == id || openByPlace[place] == id
    }

    @discardableResult
    public mutating func request(
        _ tool: SessionToolSpec, arrangement: SessionToolArrangement, hasPane: Bool
    ) -> SessionToolPlace? {
        let place = arrangement.place(of: tool)
        guard place != .off, hasPane else { return nil }
        pending[place] = tool.id
        return place
    }

    public mutating func present(_ id: SessionToolID, at place: SessionToolPlace) {
        guard pending[place] == id else { return }
        pending[place] = nil
        openByPlace[place] = id
    }

    public mutating func close(_ place: SessionToolPlace) {
        pending[place] = nil
        openByPlace[place] = nil
    }

    public mutating func close(_ id: SessionToolID) {
        for place in SessionToolPlace.allCases {
            if pending[place] == id { pending[place] = nil }
            if openByPlace[place] == id { openByPlace[place] = nil }
        }
    }
}
