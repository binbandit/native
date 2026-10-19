import Modes
import NativeCommands

extension CommandID {
    static let sessionNextMode: Self = "session.nextMode"
    static let modesEdit: Self = "modes.edit"

    /// "Debug Mode": one per mode, so a shortcut given to one puts the task in view in it.
    static func modeUse(_ id: Mode.ID) -> Self {
        Self("mode.\(id.rawValue)")
    }
}

extension NativeCommand {
    /// Next Mode (⌃⇧M), Edit Modes…, and a command per built-in mode, for the task in the frontmost
    /// window. Their keys are in `docs/keyboard.md`, Session settings.
    static func modes(_ modes: TaskModes, settings: SettingsPresentation) -> [NativeCommand] {
        [
            NativeCommand(
                .sessionNextMode, title: "Next Mode", category: .composer,
                systemImage: "arrow.trianglehead.2.clockwise",
                keywords: ["plan", "ask", "debug", "review", "build", "cycle"]
            ) { context in
                guard let session = context.session else { return }
                Task { await modes.selectNext(in: session) }
            }
            .available(canChangeMode),

            NativeCommand(
                .modesEdit, title: "Edit Modes…", category: .composer, systemImage: "slider.horizontal.3",
                keywords: ["custom", "instructions", "new mode"]
            ) { _ in
                settings.open(.modes)
            },
        ] + Mode.builtIn.map { use($0, in: modes) }
    }

    /// A command for each mode of the user's and of the projects', named after it.
    static func modeUses(_ modesToUse: [Mode], in modes: TaskModes) -> [NativeCommand] {
        modesToUse.map { use($0, in: modes) }
    }

    private static func use(_ mode: Mode, in modes: TaskModes) -> NativeCommand {
        NativeCommand(
            .modeUse(mode.id), title: "\(mode.name) Mode", category: .composer, systemImage: mode.symbol,
            keywords: ["mode", mode.summary]
        ) { context in
            guard let session = context.session else { return }
            Task { await modes.select(mode.id, in: session) }
        }
        .toggles { context in
            context.session.map { modes.mode(of: $0).id == mode.id } ?? false
        }
        .available { context in
            guard canChangeMode(context), let session = context.session else { return false }
            return modes.catalog(for: session).mode(mode.id) != nil
        }
    }

    /// A task that takes prompts, with its agent there to change settings.
    private static func canChangeMode(_ context: CommandContext) -> Bool {
        guard let session = context.session else { return false }
        return session.acceptsPrompts && session.phase != .disconnected && session.phase != .loading
    }
}
