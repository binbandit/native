import Foundation

/// A folder the user works in. Its sessions are whatever the agents list for it.
struct Project: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let url: URL
    /// Where the folder is. Projects saved before hosts existed are on this Mac.
    let host: HostID

    init(id: UUID = UUID(), url: URL, host: HostID = .local) {
        self.id = id
        self.url = url
        self.host = host
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        host = try container.decodeIfPresent(HostID.self, forKey: .host) ?? .local
    }

    var name: String {
        url.lastPathComponent
    }

    /// The folder as agents take it, for `cwd`.
    var path: String {
        url.folderPath
    }
}
