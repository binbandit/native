/// Where the user put each tool. Only places that differ from a tool's default are kept, so a
/// tool whose default changes moves for everyone who never moved it themselves.
public struct SessionToolArrangement: Equatable, Sendable {
    private var choices: [SessionToolID: SessionToolPlace]

    public init() {
        choices = [:]
    }

    /// The user's place for the tool if it can live there, else its default.
    public func place(of tool: SessionToolSpec) -> SessionToolPlace {
        guard let choice = choices[tool.id], tool.places.contains(choice) else { return tool.defaultPlace }
        return choice
    }

    /// Puts the tool in `place`, if it can live there.
    public mutating func move(_ tool: SessionToolSpec, to place: SessionToolPlace) {
        guard tool.places.contains(place) else { return }
        choices[tool.id] = place == tool.defaultPlace ? nil : place
    }

    /// Whether every tool is where it starts.
    public var isDefault: Bool { choices.isEmpty }

    public mutating func reset() {
        choices = [:]
    }
}

extension SessionToolArrangement: Codable {
    /// Saved as `{"terminal": "side"}`. A place this version doesn't know (a later one wrote it)
    /// is skipped rather than failing the rest, and the tool takes its default.
    public init(from decoder: any Decoder) throws {
        let saved = try decoder.singleValueContainer().decode([String: String].self)
        choices = Dictionary(
            uniqueKeysWithValues: saved.compactMap { id, place in
                SessionToolPlace(rawValue: place).map { (SessionToolID(rawValue: id), $0) }
            })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: choices.map { ($0.rawValue, $1.rawValue) }))
    }
}
