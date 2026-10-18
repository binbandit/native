import NativeCommands
import Observation

/// Settings ▸ Keyboard Shortcuts' editing: which command is recording, and a recorded shortcut
/// that's waiting on the user because another command has it or it can't be used.
@MainActor
@Observable
final class ShortcutEditor {
    /// A recorded shortcut another command already has: the user swaps, replaces or cancels.
    struct Conflict: Equatable {
        let command: NativeCommand.ID
        let shortcut: KeyShortcut
        let other: NativeCommand.ID
    }

    /// Something the user tried that didn't work, shown under the command's row.
    struct Problem: Equatable {
        let command: NativeCommand.ID
        let message: String
    }

    let registry: CommandRegistry
    private(set) var recording: NativeCommand.ID?
    /// The modifiers held while recording, shown as they're pressed.
    private(set) var heldModifiers: KeyShortcut.Modifiers = []
    private(set) var conflict: Conflict?
    private(set) var problem: Problem?

    @ObservationIgnored private let recorder = PlatformKeyRecorder()

    init(registry: CommandRegistry) {
        self.registry = registry
    }

    func startRecording(_ id: NativeCommand.ID) {
        guard !registry.isLocked else { return }
        conflict = nil
        problem = nil
        heldModifiers = []
        recording = id
        recorder.start { [weak self] in
            self?.heldModifiers = $0
        } onKey: { [weak self] in
            self?.press($0)
        }
    }

    func stopRecording() {
        recorder.stop()
        recording = nil
        heldModifiers = []
    }

    /// A key pressed while recording. Escape cancels; Delete on its own removes the shortcut.
    func press(_ shortcut: KeyShortcut?) {
        guard let id = recording else { return }
        guard let shortcut else {
            problem = Problem(command: id, message: "That key can't be part of a shortcut.")
            return
        }
        switch (shortcut.key, shortcut.modifiers.isEmpty) {
        case (.escape, true):
            stopRecording()
        case (.delete, true), (.forwardDelete, true):
            stopRecording()
            remove(id)
        default:
            if let rejection = registry.rejection(for: shortcut) {
                // Keep recording, so the next try is one key press away.
                problem = Problem(command: id, message: rejection)
                return
            }
            stopRecording()
            assign(shortcut, to: id)
        }
    }

    func remove(_ id: NativeCommand.ID) {
        conflict = nil
        problem = nil
        registry.assign(nil, to: id, resolving: .replace)
    }

    /// Back to the default, unless another command has it now; then it's a conflict to resolve.
    func reset(_ id: NativeCommand.ID) {
        problem = nil
        guard let original = registry.bindings.defaults[id] else {
            registry.reset(id)
            return
        }
        assign(original, to: id)
    }

    func resolve(_ resolution: ShortcutBindings.Resolution) {
        guard let conflict else { return }
        self.conflict = nil
        registry.assign(conflict.shortcut, to: conflict.command, resolving: resolution)
    }

    func dismissConflict() {
        conflict = nil
    }

    func dismissProblem() {
        problem = nil
    }

    private func assign(_ shortcut: KeyShortcut, to id: NativeCommand.ID) {
        problem = nil
        if let other = registry.conflict(for: shortcut, assigningTo: id) {
            conflict = Conflict(command: id, shortcut: shortcut, other: other.id)
        } else {
            conflict = nil
            registry.assign(shortcut, to: id, resolving: .replace)
        }
    }
}
