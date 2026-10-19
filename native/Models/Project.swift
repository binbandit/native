import Foundation

/// A folder the user works in. Its sessions are whatever the agents list for it.
struct Project: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let url: URL
    /// Where the folder is. Projects saved before hosts existed are on this Mac.
    let host: HostID
    /// What the user renamed it to in Native; the folder keeps its own name.
    var displayName: String?

    init(id: UUID = UUID(), url: URL, host: HostID = .local, displayName: String? = nil) {
        self.id = id
        self.url = url
        self.host = host
        self.displayName = displayName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        host = try container.decodeIfPresent(HostID.self, forKey: .host) ?? .local
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }

    /// The name Native shows: the user's, else the folder's.
    var name: String {
        displayName ?? folderName
    }

    var folderName: String {
        url.lastPathComponent
    }

    /// The folder as agents take it, for `cwd`.
    var path: String {
        url.folderPath
    }
}
