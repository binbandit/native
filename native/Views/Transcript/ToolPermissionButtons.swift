import ACP
import SwiftUI

/// One button per option, in the agent's order. These sit in content, so they're standard bordered
/// controls rather than Liquid Glass. ⌘Y allows once, ⌥⌘Y always and ⌘⇧⌫ rejects (docs/keyboard.md),
/// unless the transcript turns shortcuts off for this request (only one pending request owns them).
struct ToolPermissionButtons: View {
    let options: [PermissionOption]
    let onChoose: (PermissionOption) -> Void

    @Environment(\.legacyAskShortcutEnabled) private var legacyShortcut
    @Environment(\.permissionShortcutsEnabled) private var shortcutsEnabled

    var body: some View {
        // Long option names ("Yes, allow all edits in … during this session") may not fit in a row.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.md) {
                buttons
                Spacer(minLength: DS.Space.lg)
                shortcutHint
            }
            VStack(alignment: .leading, spacing: DS.Space.md) {
                buttons
                shortcutHint
            }
        }
    }

    private var buttons: some View {
        ForEach(options) { option in
            let button = Button(option.name, role: option.isRejection ? .destructive : nil) {
                onChoose(option)
            }
            .keyboardShortcut(shortcutsEnabled && isFirstOfItsKind(option) ? shortcut(for: option) : nil)
            if option.kind == .allowOnce {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private var shortcutHint: some View {
        if shortcutsEnabled {
            let hints = options.filter(isFirstOfItsKind).compactMap { option in
                (option.kind == .allowOnce && !legacyShortcut ? nil : Self.symbols(for: option.kind)).map {
                    "\($0) \(option.name)"
                }
            }
            Text(hints.joined(separator: "  ·  "))
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
        }
    }

    /// Options of a kind share its shortcut (Native's script approvals offer two "allow always"
    /// choices), so only the first gets it.
    private func isFirstOfItsKind(_ option: PermissionOption) -> Bool {
        options.first { $0.kind == option.kind }?.id == option.id
    }

    private func shortcut(for option: PermissionOption) -> KeyboardShortcut? {
        switch option.kind {
        case .allowOnce: legacyShortcut ? KeyboardShortcut("y", modifiers: .command) : nil
        case .allowAlways: KeyboardShortcut("y", modifiers: [.command, .option])
        case .rejectOnce: KeyboardShortcut(.delete, modifiers: [.command, .shift])
        case .rejectAlways: nil
        }
    }

    private static func symbols(for kind: PermissionOption.Kind) -> String? {
        switch kind {
        case .allowOnce: "⌘Y"
        case .allowAlways: "⌥⌘Y"
        case .rejectOnce: "⌘⇧⌫"
        case .rejectAlways: nil
        }
    }
}

extension EnvironmentValues {
    /// Whether a pending permission request answers to its shortcuts. Turn it off for all but one
    /// request when several are pending, so the shortcuts stay unambiguous.
    @Entry var permissionShortcutsEnabled = true
}
