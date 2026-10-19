import Foundation
import Modes
import Observation

/// Every mode a task can be put in: Native's own, the user's (Settings ▸ Modes, in the user
/// defaults as `modes.custom`), and each project's, read off the main thread from its checkout's
/// `.native/modes/` folder (never a task's worktree, so a branch can't supply them). Also which
/// mode new tasks start in (`modes.default`).
@MainActor
@Observable
final class ModeLibrary {
    static let shared = ModeLibrary()

    /// The user's own modes, in their order.
    private(set) var custom: [Mode] {
        didSet {
            if let data = try? JSONEncoder().encode(custom) {
                defaults.set(data, forKey: Self.customKey)
            }
            changed()
        }
    }
    /// The mode new tasks start in; Build unless the user picks another.
    var defaultMode: Mode.ID {
        didSet { defaults.set(defaultMode.rawValue, forKey: Self.defaultKey) }
    }
    /// What each project's folder held when last read, by `key(for:)`.
    private(set) var projects: [String: ProjectModes] = [:] {
        didSet { changed() }
    }

    /// Told when the modes change, so each has its command (`ModesWiring`).
    @ObservationIgnored var changed: () -> Void = {}
    @ObservationIgnored private var reading: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    private static let customKey = "modes.custom"
    private static let defaultKey = "modes.default"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        custom =
            defaults.data(forKey: Self.customKey).flatMap { try? JSONDecoder().decode([Mode].self, from: $0) } ?? []
        defaultMode = defaults.string(forKey: Self.defaultKey).map(Mode.ID.init(rawValue:)) ?? .build
    }

    /// The modes a task in the project at `root` can be in, in the picker's order.
    func catalog(forProjectAt root: URL?) -> ModeCatalog {
        ModeCatalog(custom: custom, project: root.map { projectModes(at: $0).modes.map(\.mode) } ?? [])
    }

    /// The mode new tasks start in, while it still exists.
    var startingMode: Mode {
        catalog(forProjectAt: nil).mode(defaultMode) ?? .build
    }

    // MARK: - Projects

    /// A path with symlinks resolved and no trailing slash, as Native keys projects elsewhere.
    static func key(for root: URL) -> String {
        GitSettings.key(for: root)
    }

    /// The project's modes as last read; `refresh(projectAt:)` reads them again.
    func projectModes(at root: URL) -> ProjectModes {
        projects[Self.key(for: root)] ?? ProjectModes()
    }

    func hasRead(projectAt root: URL) -> Bool {
        projects[Self.key(for: root)] != nil
    }

    /// Reads the project's modes folder again, off the main thread. A read under way is shared.
    func refresh(projectAt root: URL) {
        let key = Self.key(for: root)
        guard reading[key] == nil else { return }
        reading[key] = Task {
            let modes = await Self.read(root)
            if projects[key] != modes {
                projects[key] = modes
            }
            reading[key] = nil
        }
    }

    @concurrent
    private static func read(_ root: URL) async -> ProjectModes {
        ProjectModes.read(in: root)
    }

    // MARK: - The user's own

    func mode(_ id: Mode.ID) -> Mode? {
        custom.first { $0.id == id }
    }

    /// Adds a mode of the user's own; ⌘Z takes it away again.
    func add(_ mode: Mode, undoManager: UndoManager? = nil) {
        custom.append(mode)
        undoManager?.registerUndo(withTarget: self) { library in
            MainActor.assumeIsolated { library.remove(mode.id, undoManager: undoManager) }
        }
        undoManager?.setActionName("Add Mode")
    }

    func update(_ mode: Mode, undoManager: UndoManager? = nil) {
        guard let index = custom.firstIndex(where: { $0.id == mode.id }), custom[index] != mode else { return }
        let previous = custom[index]
        custom[index] = mode
        undoManager?.registerUndo(withTarget: self) { library in
            MainActor.assumeIsolated { library.update(previous, undoManager: undoManager) }
        }
        undoManager?.setActionName("Edit Mode")
    }

    /// Removes a mode of the user's own; ⌘Z puts it back in its place. Tasks in it go back to Build
    /// the next time they're looked at.
    func remove(_ id: Mode.ID, undoManager: UndoManager? = nil) {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return }
        let mode = custom.remove(at: index)
        let wasDefault = defaultMode == id
        if wasDefault {
            defaultMode = .build
        }
        undoManager?.registerUndo(withTarget: self) { library in
            MainActor.assumeIsolated {
                library.custom.insert(mode, at: min(index, library.custom.count))
                if wasDefault { library.defaultMode = id }
                undoManager?.registerUndo(withTarget: library) { library in
                    MainActor.assumeIsolated { library.remove(id, undoManager: undoManager) }
                }
            }
        }
        undoManager?.setActionName("Delete Mode")
    }

    /// A name no other mode of the user's has, for a new one or a copy: "Review copy", "Review copy 2".
    func freeName(for name: String) -> String {
        let taken = Set((Mode.builtIn + custom).map { $0.name.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var candidate = "\(name) copy"
        var number = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(name) copy \(number)"
            number += 1
        }
        return candidate
    }
}
