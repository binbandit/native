import Foundation

/// A project the home page can start tasks in. `ID` is whatever identifies a project in the app.
public struct HomeProject<ID: Hashable>: Identifiable {
    public let id: ID
    public let name: String
    /// The project's folder, for its location.
    public let url: URL

    public init(id: ID, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }

    /// Where the folder is, with the home folder as `~`, as the Finder and Terminal show it.
    var location: String {
        (url.deletingLastPathComponent().path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
