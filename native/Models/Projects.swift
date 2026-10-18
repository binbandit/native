import ACP
import Foundation
import Observation
import SwiftUI

/// The projects open in the sidebar, in the user's order, and the ones archived out of it,
/// remembered across launches.
@Observable
final class Projects {
    private(set) var all: [Project] = [] {
        didSet { save() }
    }
    /// Projects the user archived, most recent first. Their sessions stay with the agents.
    private(set) var archived: [Project] = [] {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "projects"
    private static let archivedKey = "archivedProjects"
    /// Where the single workspace of earlier versions was remembered.
    private static let legacyWorkspaceKey = "workspace"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
            let projects = try? JSONDecoder().decode([Project].self, from: data)
        {
            all = projects
        } else if let path = defaults.string(forKey: Self.legacyWorkspaceKey) {
            all = [Project(id: UUID(), url: URL(filePath: path, directoryHint: .isDirectory))]
            // Assigning in init doesn't run `didSet`, and the project's id has to stick.
            save()
        }
        if let data = defaults.data(forKey: Self.archivedKey),
            let projects = try? JSONDecoder().decode([Project].self, from: data)
        {
            archived = projects
        }
    }

    func project(_ id: Project.ID) -> Project? {
        all.first { $0.id == id }
    }

    /// Adds a folder at the end, or returns its project if it's already open.
    @discardableResult
    func add(_ url: URL) -> Project {
        if let existing = all.first(where: { SessionFolder.isSame($0.path, url.folderPath) }) {
            return existing
        }
        let project = Project(id: UUID(), url: url)
        all.append(project)
        return project
    }

    func remove(_ id: Project.ID) {
        all.removeAll { $0.id == id }
    }

    /// Puts a removed project back where it was, for undo.
    func restore(_ project: Project, at index: Int) {
        guard self.project(project.id) == nil else { return }
        all.insert(project, at: min(index, all.count))
    }

    /// Moves a project out of the sidebar into the archive, returning where it was.
    @discardableResult
    func archive(_ id: Project.ID) -> Int? {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return nil }
        archived.insert(all.remove(at: index), at: 0)
        return index
    }

    /// Brings an archived project back to the sidebar, at `index` or the end.
    func unarchive(_ id: Project.ID, at index: Int? = nil) {
        guard let position = archived.firstIndex(where: { $0.id == id }) else { return }
        let project = archived.remove(at: position)
        all.insert(project, at: min(index ?? all.count, all.count))
    }

    /// Forgets an archived project entirely.
    func removeArchived(_ id: Project.ID) {
        archived.removeAll { $0.id == id }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        all.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.key)
        }
        if let data = try? JSONEncoder().encode(archived) {
            defaults.set(data, forKey: Self.archivedKey)
        }
    }
}
