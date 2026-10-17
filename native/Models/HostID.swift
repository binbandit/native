/// The machine a project lives on and its agents run on: this Mac, or a remote Native host.
struct HostID: Hashable, Codable, Sendable {
    let rawValue: String

    static let local = HostID(rawValue: "local")

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
