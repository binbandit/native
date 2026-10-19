import Foundation

/// The actions a team commits with the repo, in `.native/actions.json` at the project's root:
///
///     {
///       "actions": [
///         { "name": "Test", "command": "bun run test", "icon": "checkmark.seal" },
///         { "name": "Web", "command": "bun run dev", "directory": "apps/web" },
///         { "name": "Install", "command": "bun install", "runIn": "background" }
///       ]
///     }
///
/// `name` and `command` are required. `directory` is relative to the task's worktree, or to the
/// project's checkout with `"relativeTo": "project"`. `runIn` is `terminal` (the default) or
/// `background`. Unknown keys are ignored, so the file can grow; an entry that can't be used is
/// skipped with the reason, and the rest still load.
public enum ProjectActionFile {
    /// Where the file lives, relative to the project's root.
    public static let path = ".native/actions.json"

    /// What reading the file found.
    public enum Contents: Hashable, Sendable {
        /// The project has no file.
        case none
        /// The usable actions, in the file's order, and why any others were skipped.
        case actions([ProjectAction], skipped: [String])
        /// The file isn't JSON in the expected shape; the reason, for the user.
        case unreadable(String)

        public var actions: [ProjectAction] {
            if case .actions(let actions, _) = self { actions } else { [] }
        }
    }

    public static func read(in root: URL) -> Contents {
        let url = root.appending(path: path)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .none }
        do {
            return decode(try Data(contentsOf: url))
        } catch {
            return .unreadable("Couldn't read \(path): \(error.localizedDescription)")
        }
    }

    public static func decode(_ data: Data) -> Contents {
        let file: FileShape
        do {
            file = try JSONDecoder().decode(FileShape.self, from: data)
        } catch DecodingError.dataCorrupted {
            return .unreadable("\(path) isn't valid JSON.")
        } catch {
            return .unreadable("\(path) needs an \"actions\" list.")
        }
        var actions: [ProjectAction] = []
        var skipped: [String] = []
        for (index, entry) in file.actions.enumerated() {
            switch entry.action(existing: actions) {
            case .success(let action): actions.append(action)
            case .failure(let reason): skipped.append("Action \(index + 1): \(reason.message)")
            }
        }
        return .actions(actions, skipped: skipped)
    }

    /// The file written out, for a team adding the user's actions to the repo.
    public static func encode(_ actions: [ProjectAction]) throws -> Data {
        let entries = actions.map(Entry.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(FileShape(actions: entries))
    }

    private struct FileShape: Codable {
        var actions: [Entry]
    }

    /// One entry as written, every field optional, so a bad entry is reported rather than failing
    /// the whole file.
    private struct Entry: Codable {
        var name: String?
        var command: String?
        var icon: String?
        var directory: String?
        var relativeTo: String?
        var runIn: String?

        init(_ action: ProjectAction) {
            name = action.name
            command = action.command
            icon = action.icon
            directory = action.directory.path.isEmpty ? nil : action.directory.path
            relativeTo = action.directory.base == .worktree ? nil : action.directory.base.rawValue
            runIn = action.presentation == .terminal ? nil : action.presentation.rawValue
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // A wrong type in one field skips this entry, not the file.
            name = try? container.decodeIfPresent(String.self, forKey: .name)
            command = try? container.decodeIfPresent(String.self, forKey: .command)
            icon = try? container.decodeIfPresent(String.self, forKey: .icon)
            directory = try? container.decodeIfPresent(String.self, forKey: .directory)
            relativeTo = try? container.decodeIfPresent(String.self, forKey: .relativeTo)
            runIn = try? container.decodeIfPresent(String.self, forKey: .runIn)
        }

        struct Problem: Error {
            let message: String
        }

        func action(existing: [ProjectAction]) -> Result<ProjectAction, Problem> {
            let name = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let command = (command ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .failure(Problem(message: "it has no \"name\".")) }
            guard !command.isEmpty else { return .failure(Problem(message: "“\(name)” has no \"command\".")) }
            let base = relativeTo.map { ProjectAction.Directory.Base(rawValue: $0) }
            guard let base = base ?? .worktree else {
                return .failure(Problem(message: "“\(name)”: \"relativeTo\" is \"worktree\" or \"project\"."))
            }
            let presentation = runIn.map { ProjectAction.Presentation(rawValue: $0) }
            guard let presentation = presentation ?? .terminal else {
                return .failure(Problem(message: "“\(name)”: \"runIn\" is \"terminal\" or \"background\"."))
            }
            // Two entries with the same name still get ids of their own.
            let key = ProjectAction.key(forName: name) ?? "action"
            let taken = Set(existing.map(\.id))
            let id = sequence(first: 1) { $0 + 1 }.lazy
                .map { ProjectAction.ID.repository($0 == 1 ? key : "\(key)-\($0)") }
                .first { !taken.contains($0) }
            return .success(
                ProjectAction(
                    id: id ?? .repository(key),
                    name: name,
                    command: command,
                    icon: icon?.isEmpty == false ? icon : nil,
                    directory: .init(base: base, path: directory ?? ""),
                    presentation: presentation
                ))
        }
    }
}
