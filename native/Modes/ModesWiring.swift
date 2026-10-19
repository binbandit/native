import Modes
import NativeCommands

/// Connects modes to the rest of the app at launch: which project a task's modes come from, the
/// session hooks that send a mode's instructions and start new tasks in the default mode, and the
/// commands (Next Mode, Edit Modes…, and one per mode, kept in step as modes come and go).
@MainActor
enum ModesWiring {
    static func connect(_ registry: CommandRegistry, model: AppModel, settings: SettingsPresentation) {
        let modes = TaskModes.shared
        modes.projectRoot = { session in
            model.catalog.lookup(session.key).flatMap { model.projects.project($0.project)?.url }
        }
        model.sessionHooks.preamble = { session, delivered in modes.preamble(for: session, delivered: delivered) }
        model.sessionHooks.taskStarted = { session, earlier in
            await modes.taskStarted(session, continuing: earlier)
        }
        registry.register(NativeCommand.modes(modes, settings: settings))
        var registered: Set<CommandID> = []
        let sync = {
            let library = modes.library
            var seen: Set<Mode.ID> = []
            let all = (library.custom + library.projects.values.flatMap { $0.modes.map(\.mode) })
                .filter { seen.insert($0.id).inserted }
            let commands = NativeCommand.modeUses(all, in: modes)
            let ids = Set(commands.map(\.id))
            registry.unregister(registered.subtracting(ids))
            registry.register(commands)
            registered = ids
        }
        modes.library.changed = sync
        sync()
    }
}
