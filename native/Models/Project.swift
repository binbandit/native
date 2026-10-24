import Foundation

/// A repository the user works in. Its sessions are whatever the agents list for it. Each device
/// has its own checkout: this Mac's is `url`, a paired host's is in `checkouts`, and the project is
/// the same on all of them because `repository` says so (`docs/durability.md`, "Host identity and
/// many hosts").
struct Project: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// This Mac's checkout.
    let url: URL
    /// Legacy: projects saved before paired hosts were on this Mac. Checkouts elsewhere are in
    /// `checkouts`.
    let host: HostID
    /// What the user renamed it to in Native; the folder keeps its own name.
    var displayName: String?
    /// The repository the folder is a checkout of, as `ProjectRepository` reads its remote
    /// ("github.com/owner/name"); nil for a folder without a hosted remote, which is the same
    /// project on another device only where the user says so.
    var repository: String?
    /// That remote's URL as this Mac's checkout has it, for cloning the project onto another device.
    var remoteURL: String?
    /// Checkouts on paired hosts, one per host.
    var checkouts: [ProjectCheckout]

    init(
        id: UUID = UUID(), url: URL, host: HostID = .local, displayName: String? = nil, repository: String? = nil,
        remoteURL: String? = nil, checkouts: [ProjectCheckout] = []
    ) {
        self.id = id
        self.url = url
        self.host = host
        self.displayName = displayName
        self.repository = repository
        self.remoteURL = remoteURL
        self.checkouts = checkouts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        host = try container.decodeIfPresent(HostID.self, forKey: .host) ?? .local
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        repository = try container.decodeIfPresent(String.self, forKey: .repository)
        remoteURL = try container.decodeIfPresent(String.self, forKey: .remoteURL)
        checkouts = try container.decodeIfPresent([ProjectCheckout].self, forKey: .checkouts) ?? []
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

    /// The project's folder on `device`, as its agents take it; nil where it has no checkout.
    func checkoutPath(on device: SessionDevice) -> String? {
        switch device {
        case .thisMac: path
        case .remote(let host): checkouts.first { $0.host == host }?.path
        }
    }
}

/// A project's folder on a paired host.
nonisolated struct ProjectCheckout: Hashable, Codable, Sendable {
    let host: RemoteHostID
    /// The folder on that host, as its agents take it.
    var path: String
    /// Explicitly selected task worktrees outside the host's managed worktree folder.
    var taskFolders: [String]?
}
