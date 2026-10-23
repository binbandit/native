import Foundation

/// The project a folder belongs to, and the branch checked out there.
struct TaskScriptFolder: Hashable, Sendable {
    var projectRoot: URL
    var branch: String?
}
