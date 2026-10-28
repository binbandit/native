import Foundation

/// Native-owned names outlive closing a project. The file identity follows a folder moved on the
/// same volume; the path also keeps names when a folder is temporarily unavailable.
@MainActor public final class ProjectNameStore {
    private struct Entry: Codable {
        var name: String
        var paths: Set<String>
        var fileID: String?
    }

    private let defaults: UserDefaults
    private let key = "projectDisplayNames"
    private var entries: [Entry]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    public func name(for url: URL) -> String? {
        index(for: url).map { entries[$0].name }
    }

    public func rename(_ url: URL, to name: String?) {
        let index = index(for: url)
        if let name = ProjectName.normalized(name, folderName: url.lastPathComponent) {
            if let index {
                entries[index].name = name
                entries[index].paths.insert(path(for: url))
                entries[index].fileID = fileID(for: url) ?? entries[index].fileID
            } else {
                entries.append(Entry(name: name, paths: [path(for: url)], fileID: fileID(for: url)))
            }
        } else if let index {
            entries.remove(at: index)
        }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }

    private func index(for url: URL) -> Int? {
        let id = fileID(for: url)
        if let id, let index = entries.firstIndex(where: { $0.fileID == id }) { return index }
        // A new folder at a moved folder's old path must not inherit or clear that folder's name.
        return entries.firstIndex { $0.paths.contains(path(for: url)) && (id == nil || $0.fileID == nil) }
    }

    private func path(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func fileID(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path(for: url)),
            let volume = attributes[.systemNumber] as? NSNumber,
            let file = attributes[.systemFileNumber] as? NSNumber,
            let created = attributes[.creationDate] as? Date
        else { return nil }
        return "\(volume):\(file):\(created.timeIntervalSince1970)"
    }
}
