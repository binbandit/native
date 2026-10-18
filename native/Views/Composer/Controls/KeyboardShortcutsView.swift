import SwiftUI

/// Every keyboard shortcut in docs/keyboard.md, opened from the composer's help button like Factory's
/// shortcuts sheet. Keep it in step with that table.
struct KeyboardShortcutsView: View {
    @AppStorage(FollowUpBehavior.storageKey) private var followUp = FollowUpBehavior.defaultValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Text("Keyboard Shortcuts")
                .font(.dsTitle3)
            HStack(alignment: .top, spacing: DS.Space.xxxl) {
                column {
                    header("Sending", isFirst: true)
                    row("Send, or \(followUp.title.lowercased()) while the agent works", ["↩"])
                    row("Send, or \(followUp.opposite.title.lowercased()) while the agent works", ["⌘↩"])
                    row("New line", ["⇧↩"], ["⌥↩"])
                    row("Stop the turn", ["esc"], ["⌘."])
                    row("Last prompt, or edit the last queued message", ["↑"], note: "in an empty composer")
                    header("Slash Commands")
                    row("Open the command list", ["/"], note: "at the start")
                    row("Move the selection", ["↑"], ["↓"])
                    row("Insert the selected command", ["↩"], ["⇥"])
                    row("Close the list", ["esc"])
                    header("Permission Requests")
                    row("Allow once", ["⌘Y"])
                    row("Allow always", ["⌥⌘Y"])
                    row("Reject", ["⇧⌘⌫"])
                }
                column {
                    header("Sessions and Navigation", isFirst: true)
                    row("New session", ["⌘N"])
                    row("New session with…", ["⌥⌘N"])
                    row("Open folder", ["⌘O"])
                    row("Focus the composer", ["⌘L"])
                    row("Go to a session in the sidebar", ["⌘1 – ⌘9"])
                    row("Next or previous session", ["⌃⇥"], ["⌃⇧⇥"])
                    row("Rename the selected session", ["↩"], note: "in the sidebar")
                    row("Show or hide the sidebar", ["⌃⌘S"])
                    row("Show or hide the subagent inspector", ["⌥⌘I"])
                    header("Session Settings")
                    row("Next permission mode", ["⇧⌘M"])
                    row("Model picker", ["⇧⌘E"])
                    header("Attachments")
                    row("Attach files", ["⌘U"])
                    row("Paste files or an image", ["⌘V"])
                }
            }
            HStack {
                Text("Tab and Shift-Tab move between controls when Keyboard Navigation is on in System Settings.")
                    .foregroundStyle(.dsTextTertiary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.ds(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .font(.dsBody)
        }
        .padding(DS.Space.xxl)
        .fixedSize()
        .background(.dsSurface)
    }

    /// One column of sections, so keys line up down the whole column.
    private func column(@ViewBuilder rows: () -> some View) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
            rows()
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextPrimary)
        .frame(width: ComposerMetrics.shortcutsColumnWidth, alignment: .topLeading)
    }

    private func header(_ title: String, isFirst: Bool = false) -> some View {
        GridRow {
            Text(title)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextSecondary)
                .padding(.top, isFirst ? 0 : DS.Space.lg)
                .gridCellColumns(2)
        }
    }

    /// One shortcut: what it does, then each key combination that does it.
    private func row(_ title: String, _ combinations: [String]..., note: String? = nil) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                if let note {
                    Text(note)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            HStack(spacing: DS.Space.xs) {
                ForEach(combinations.indices, id: \.self) { index in
                    if index > 0 {
                        Text("or")
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                    ForEach(combinations[index], id: \.self) { keys in
                        Kbd(keys)
                    }
                }
            }
            .gridColumnAlignment(.trailing)
        }
    }
}
