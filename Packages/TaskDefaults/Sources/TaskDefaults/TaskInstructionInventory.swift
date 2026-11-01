import Foundation

/// Reads only metadata at plugin-declared paths, never credentials or instruction contents.
public enum TaskInstructionInventory {
    public static func read(
        _ locations: [TaskInstructionLocation], home: URL, project: URL?, environment: [String: String]
    ) -> [TaskInstructionFile] {
        var result: [TaskInstructionFile] = []
        for location in locations {
            guard let base = location.scope == .project ? project : home else { continue }
            let directory =
                location.environmentKey.flatMap { environment[$0] }.map { URL(filePath: $0) }
                ?? base.appending(path: location.directory)
            for name in location.names {
                let url = directory.appending(path: name)
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                    attributes[.type] as? FileAttributeType == .typeRegular
                else { continue }
                if !result.contains(where: { $0.url == url }) {
                    result.append(.init(url: url, scope: location.scope, bytes: attributes[.size] as? Int))
                }
                if location.firstExisting { break }
            }
        }
        return result
    }
}
