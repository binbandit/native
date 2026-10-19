import Foundation

/// Every mode a task can be in, grouped as the picker lists them: Native's own, the user's, then
/// the task's project's.
public struct ModeCatalog: Hashable, Sendable {
    public var builtIn: [Mode]
    public var custom: [Mode]
    public var project: [Mode]

    public init(builtIn: [Mode] = Mode.builtIn, custom: [Mode] = [], project: [Mode] = []) {
        self.builtIn = builtIn
        self.custom = custom
        self.project = project
    }

    public var all: [Mode] {
        builtIn + custom + project
    }

    public func mode(_ id: Mode.ID) -> Mode? {
        all.first { $0.id == id }
    }

    /// The mode after `id` in the picker's order, wrapping around, for the key that cycles them.
    public func next(after id: Mode.ID) -> Mode {
        let modes = all
        guard let index = modes.firstIndex(where: { $0.id == id }) else { return modes.first ?? .build }
        return modes[(index + 1) % modes.count]
    }
}

/// A project's shared modes, read from its `.native/modes/` folder.
public struct ProjectModes: Hashable, Sendable {
    public var modes: [ModeFile.Parsed] = []
    /// Files that couldn't be used, with why.
    public var problems: [ModeFile.Problem] = []

    public init(modes: [ModeFile.Parsed] = [], problems: [ModeFile.Problem] = []) {
        self.modes = modes
        self.problems = problems
    }

    /// Reads every `.md` file in `root`'s modes folder, in name order. A missing folder is no
    /// modes; a mode named like one before it (or like Native's own) is a problem, not a second
    /// mode of the same name.
    public static func read(in root: URL, fileManager: FileManager = .default) -> ProjectModes {
        let folder = root.appending(path: ModeFile.folder, directoryHint: .isDirectory)
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return ProjectModes() }
        let named = files.filter { $0.pathExtension == ModeFile.fileExtension }
            .map { ($0.lastPathComponent, $0) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        return ProjectModes(
            files: named.map { name, url in
                (name, Result { try String(contentsOf: url, encoding: .utf8) })
            })
    }

    /// Parses files already read, as `read(in:)` does.
    init(files: [(name: String, contents: Result<String, any Error>)]) {
        var taken = Set(Mode.builtIn.map { $0.name.lowercased() })
        for (name, contents) in files {
            switch contents {
            case .failure:
                problems.append(ModeFile.Problem(file: name, reason: "It couldn't be read as UTF-8 text."))
            case .success(let text):
                switch ModeFile.parse(text, fileName: name, source: .project) {
                case .failure(let problem):
                    problems.append(problem)
                case .success(let parsed):
                    guard taken.insert(parsed.mode.name.lowercased()).inserted else {
                        problems.append(
                            ModeFile.Problem(
                                file: name,
                                reason: "Another mode is already called \(parsed.mode.name). Give this one its own name."
                            ))
                        continue
                    }
                    modes.append(parsed)
                }
            }
        }
    }
}
