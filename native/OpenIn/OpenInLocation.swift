import Foundation

/// Where a task's folder lives. Today that's always this Mac. Remote Native Hosts (over SSH) will
/// add a case; the catalog already records how each app opens a folder on a host
/// (`OpenInTarget.remote`), so the menus will list only the apps that can.
nonisolated enum OpenInLocation: Hashable, Sendable {
    case local(URL)

    /// What Copy Path copies.
    var path: String {
        switch self {
        case .local(let folder): folder.path(percentEncoded: false)
        }
    }
}
