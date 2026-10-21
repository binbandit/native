/// What the session screen needs to place a tool: the places it can live and the one it starts in.
/// What the tool shows, and its views, stay with its feature.
public struct SessionToolSpec: Identifiable, Hashable, Sendable {
    public let id: SessionToolID
    /// In the order a menu of them lists them.
    public let places: [SessionToolPlace]
    public let defaultPlace: SessionToolPlace

    /// - Parameter places: Where it can live; leave out `off` for a tool that can't be turned off.
    public init(id: SessionToolID, places: [SessionToolPlace], defaultPlace: SessionToolPlace) {
        assert(places.contains(defaultPlace), "\(id) can't start somewhere it can't live")
        self.id = id
        self.places = places
        self.defaultPlace = defaultPlace
    }
}
