import Foundation
import Observation
import SwiftUI

/// A folder the user works in. Its sessions are whatever the agents list for it.
struct Project: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let url: URL

    var name: String {
        url.lastPathComponent
    }

    /// The folder as agents take it, for `cwd`.
    var path: String {
        url.path(percentEncoded: false)
    }
}

/// The projects open in the sidebar, in the user's order, remembered across launches.
@Observable
final class Projects {
    private(set) var all: [Project] = [] {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "projects"
    /// Where the single workspace of earlier versions was remembered.
    private static let legacyWorkspaceKey = "workspace"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let projects = try? JSONDecoder().decode([Project].self, from: data) {
            all = projects
        } else if let path = defaults.string(forKey: Self.legacyWorkspaceKey) {
            all = [Project(id: UUID(), url: URL(filePath: path, directoryHint: .isDirectory))]
        }
    }

    func project(_ id: Project.ID) -> Project? {
        all.first { $0.id == id }
    }

    /// Adds a folder at the end, or returns its project if it's already open.
    @discardableResult
    func add(_ url: URL) -> Project {
        let url = url.standardizedFileURL
        if let existing = all.first(where: { $0.url.standardizedFileURL == url }) {
            return existing
        }
        let project = Project(id: UUID(), url: url)
        all.append(project)
        return project
    }

    func remove(_ id: Project.ID) {
        all.removeAll { $0.id == id }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        all.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
