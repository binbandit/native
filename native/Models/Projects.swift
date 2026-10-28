import ACP
import Foundation
import Observation
import ProjectNames
import SwiftUI

/// The projects open in the sidebar, in the user's order, and the ones archived out of it,
/// remembered across launches.
@Observable
final class Projects {
    private var openProjects: [Project] = [] {
        didSet { save() }
    }
    /// Projects the user archived, most recent first. Their sessions stay with the agents.
    private var archivedProjects: [Project] = [] {
        didSet { save() }
    }

    var all: [Project] { Array(resolved(openProjects + archivedProjects).prefix(openProjects.count)) }
    var archived: [Project] { Array(resolved(openProjects + archivedProjects).dropFirst(openProjects.count)) }

    @ObservationIgnored private let names: ProjectNameStore
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "projects"
    private static let archivedKey = "archivedProjects"
    /// Where the single workspace of earlier versions was remembered.
    private static let legacyWorkspaceKey = "workspace"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = ProjectNameStore(defaults: defaults)
        if let data = defaults.data(forKey: Self.key),
            let projects = try? JSONDecoder().decode([Project].self, from: data)
        {
            openProjects = projects
        } else if let path = defaults.string(forKey: Self.legacyWorkspaceKey) {
            openProjects = [Project(id: UUID(), url: URL(filePath: path, directoryHint: .isDirectory))]
            // Assigning in init doesn't run `didSet`, and the project's id has to stick.
            save()
        }
        if let data = defaults.data(forKey: Self.archivedKey),
            let projects = try? JSONDecoder().decode([Project].self, from: data)
        {
            archivedProjects = projects
        }
        names.migrateLegacyNames(
            (openProjects + archivedProjects).filter { $0.host == .local }.map {
                ProjectName(url: $0.url, customName: $0.displayName)
            })
        synchronizeNames()
    }

    /// Project records cache names for rendering; the folder store is authoritative, including a
    /// cleared name. Refreshing every local record also catches aliases and moved-folder records.
    private func synchronizeNames() {
        func refreshed(_ project: Project) -> Project {
            guard project.host == .local else { return project }
            var project = project
            project.displayName = names.name(for: project.url)
            return project
        }
        openProjects = openProjects.map(refreshed)
        archivedProjects = archivedProjects.map(refreshed)
    }

    private func resolved(_ projects: [Project]) -> [Project] {
        let qualifiers = ProjectName.qualifiers(
            for: projects.map {
                ProjectName(url: $0.url, customName: $0.displayName, scope: $0.host.rawValue)
            })
        return zip(projects, qualifiers).map { project, qualifier in
            var project = project
            project.nameQualifier = qualifier
            return project
        }
    }

    func project(_ id: Project.ID) -> Project? {
        id == NoProjectLocation.id ? NoProjectLocation.group : all.first { $0.id == id }
    }

    func name(for url: URL) -> String {
        (all + archived).first { SessionFolder.isSame($0.path, url.folderPath) }?.name
            ?? names.name(for: url) ?? url.lastPathComponent
    }

    /// Adds a folder at the end, or returns its project if it's already open.
    @discardableResult
    func add(_ url: URL) -> Project {
        synchronizeNames()
        if let existing = openProjects.first(where: { SessionFolder.isSame($0.path, url.folderPath) }) {
            return project(existing.id) ?? existing
        }
        let project = Project(id: UUID(), url: url, displayName: names.name(for: url))
        openProjects.append(project)
        return self.project(project.id) ?? project
    }

    /// Names the project in Native, open or archived; nil or blank goes back to the folder's name.
    func rename(_ id: Project.ID, to name: String?) {
        guard let project = (openProjects + archivedProjects).first(where: { $0.id == id }) else { return }
        let displayName = ProjectName.normalized(name, folderName: project.folderName)
        if project.host == .local {
            names.rename(project.url, to: displayName)
            synchronizeNames()
            return
        }
        if let index = openProjects.firstIndex(where: { $0.id == id }) {
            openProjects[index].displayName = displayName
        } else if let index = archivedProjects.firstIndex(where: { $0.id == id }) {
            archivedProjects[index].displayName = displayName
        }
    }

    /// Changes a project, open or archived: its repository and checkouts on other devices
    /// (AppModel+Hosts.swift).
    func update(_ id: Project.ID, _ change: (inout Project) -> Void) {
        if let index = openProjects.firstIndex(where: { $0.id == id }) {
            change(&openProjects[index])
        } else if let index = archivedProjects.firstIndex(where: { $0.id == id }) {
            change(&archivedProjects[index])
        }
    }

    func remove(_ id: Project.ID) {
        openProjects.removeAll { $0.id == id }
    }

    /// Puts a removed project back where it was, for undo.
    func restore(_ project: Project, at index: Int) {
        guard self.project(project.id) == nil else { return }
        var project = project
        if project.host == .local { project.displayName = names.name(for: project.url) }
        openProjects.insert(project, at: min(index, openProjects.count))
    }

    /// Moves a project out of the sidebar into the archive, returning where it was.
    @discardableResult
    func archive(_ id: Project.ID) -> Int? {
        guard let index = openProjects.firstIndex(where: { $0.id == id }) else { return nil }
        archivedProjects.insert(openProjects.remove(at: index), at: 0)
        return index
    }

    /// Brings an archived project back to the sidebar, at `index` or the end.
    func unarchive(_ id: Project.ID, at index: Int? = nil) {
        guard let position = archivedProjects.firstIndex(where: { $0.id == id }) else { return }
        let project = archivedProjects.remove(at: position)
        openProjects.insert(project, at: min(index ?? openProjects.count, openProjects.count))
    }

    /// Forgets an archived project entirely.
    func removeArchived(_ id: Project.ID) {
        archivedProjects.removeAll { $0.id == id }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        openProjects.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(openProjects) {
            defaults.set(data, forKey: Self.key)
        }
        if let data = try? JSONEncoder().encode(archivedProjects) {
            defaults.set(data, forKey: Self.archivedKey)
        }
    }
}
