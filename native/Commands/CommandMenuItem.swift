import NativeCommands
import SwiftUI

/// A command as a menu bar item: its title, current shortcut, availability and action all come
/// from the registry, so remapping it in Settings changes the menu at once.
///
///     CommandMenu("Session") {
///         CommandMenuItem(.sessionArchive, in: menu)
///     }
///
/// It works out what it shows when its menu builds it, from the context the menu bar reads once for
/// all of its items (`NativeMenuBar`), and it's equal to the item it replaces while that stays the
/// same, so a focus change rebuilds only the items whose title or state it changes.
struct CommandMenuItem: View, Equatable {
    private let id: NativeCommand.ID
    private let registry: CommandRegistry
    private let title: String
    /// Nil for a command that isn't registered (yet), which shows nothing.
    private let control: Control?
    private let isEnabled: Bool
    private let shortcut: KeyboardShortcut?

    private enum Control: Equatable {
        case button
        /// A command that switches something on and off, with a checkmark while it's on.
        case toggle(isOn: Bool)
    }

    /// `title` is a shorter one where the menu says the rest ("Next Mode" in Keep Mac Awake).
    init(_ id: NativeCommand.ID, in menu: CommandMenuContext, title: String? = nil) {
        self.id = id
        registry = menu.registry
        let command = menu.registry.command(id)
        let context = menu.context
        self.title = title ?? command?.menuTitle?(context) ?? command?.title ?? ""
        control = command.map { command in command.isOn.map { Control.toggle(isOn: $0(context)) } ?? .button }
        isEnabled = command?.isAvailable(context) ?? false
        shortcut = menu.registry.keyboardShortcut(for: id)
    }

    var body: some View {
        #if DEBUG || NATIVE_PERF
        let _ = MenuBench.itemBodies += 1
        #endif
        switch control {
        case .button:
            Button(title, action: perform)
                .keyboardShortcut(shortcut)
                .disabled(!isEnabled)
        case .toggle(let isOn):
            Toggle(title, isOn: Binding(get: { isOn }, set: { _ in perform() }))
                .keyboardShortcut(shortcut)
                .disabled(!isEnabled)
        case nil:
            EmptyView()
        }
    }

    /// On the menu bar's current context: this item may have been built for an earlier one.
    private func perform() {
        registry.perform(id, in: registry.menuBarContext)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.registry === rhs.registry && lhs.title == rhs.title && lhs.control == rhs.control
            && lhs.isEnabled == rhs.isEnabled && lhs.shortcut == rhs.shortcut
    }
}
