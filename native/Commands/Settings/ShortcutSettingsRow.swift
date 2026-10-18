import NativeCommands
import SwiftUI

/// One command in Settings ▸ Keyboard Shortcuts: its name, its shortcut as a pill that records a
/// new one when clicked, a reset button once it's changed, and under it whatever needs the user (a
/// conflict to resolve, a key that can't be used).
struct ShortcutSettingsRow: View {
    let command: NativeCommand
    let editor: ShortcutEditor

    private var registry: CommandRegistry { editor.registry }
    private var isCustomized: Bool { registry.isCustomized(command.id) }

    static func rowID(_ id: NativeCommand.ID) -> SettingsRowID {
        SettingsRowID("shortcut.\(id)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.lg) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(command.title)
                        .settingsText(.bodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    if isCustomized {
                        Text("Default: \(registry.bindings.defaults[command.id]?.displayString ?? "none")")
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if isCustomized, !registry.isLocked {
                    Button("Reset to Default", systemImage: "arrow.uturn.backward") {
                        editor.reset(command.id)
                    }
                    .buttonStyle(.ds(.ghost, iconOnly: true))
                    .help("Reset to \(registry.bindings.defaults[command.id]?.displayString ?? "no shortcut")")
                }
                ShortcutRecorderPill(command: command, editor: editor)
            }
            if let conflict = editor.conflict, conflict.command == command.id {
                conflictNotice(conflict)
            }
            if let problem = editor.problem, problem.command == command.id {
                Text(problem.message)
                    .settingsText(.caption)
                    .foregroundStyle(.dsDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
        .contentShape(.rect)
        .contextMenu {
            if !registry.isLocked {
                Button("Record Shortcut", systemImage: "record.circle") { editor.startRecording(command.id) }
                Button("Remove Shortcut", systemImage: "minus.circle") { editor.remove(command.id) }
                    .disabled(registry.shortcut(for: command.id) == nil)
                Button("Reset to Default", systemImage: "arrow.uturn.backward") { editor.reset(command.id) }
                    .disabled(!isCustomized)
            }
        }
        .settingsRevealTarget(Self.rowID(command.id))
    }

    private func conflictNotice(_ conflict: ShortcutEditor.Conflict) -> some View {
        let other = registry.command(conflict.other)?.title ?? conflict.other.rawValue
        let previous = registry.shortcut(for: command.id)
        let swapDetail =
            previous.map { "Swap gives \(other) \($0.displayString)" } ?? "Swap leaves \(other) without one"
        return NoticeBanner(
            tone: .warning,
            title: "\(conflict.shortcut.displayString) is already \(other)",
            detail: "\(swapDetail); Replace leaves it without a shortcut."
        ) {
            Button("Swap") { editor.resolve(.swap) }
                .buttonStyle(.ds(.secondary))
            Button("Replace") { editor.resolve(.replace) }
                .buttonStyle(.ds(.primary))
            Button("Cancel") { editor.dismissConflict() }
                .buttonStyle(.ds(.ghost))
        }
    }
}

/// The shortcut as Conductor's pill. Clicking it records: it outlines in the accent and shows the
/// modifiers held until a key completes the shortcut. Escape cancels; Delete removes it.
private struct ShortcutRecorderPill: View {
    let command: NativeCommand
    let editor: ShortcutEditor
    @FocusState private var isFocused: Bool

    private var isRecording: Bool { editor.recording == command.id }

    var body: some View {
        let shortcut = editor.registry.shortcut(for: command.id)
        Button {
            if isRecording {
                editor.stopRecording()
            } else {
                editor.startRecording(command.id)
            }
        } label: {
            Group {
                if isRecording {
                    let held = editor.heldModifiers.glyphs
                    Text(held.isEmpty ? "Type shortcut" : held)
                        .foregroundStyle(held.isEmpty ? .dsTextTertiary : .dsTextPrimary)
                } else if let shortcut {
                    KeyGlyphs(keys: shortcut.displayString.replacingOccurrences(of: "↩", with: "↵"))
                        .foregroundStyle(.dsTextSecondary)
                } else {
                    Text("None")
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .settingsText(.bodyMedium)
            .padding(.horizontal, DS.Space.lg)
            .frame(minWidth: SettingsMetrics.selectWidth / 2, minHeight: SettingsMetrics.controlHeight)
            .background(.dsSurfaceSunken, in: .capsule)
            .overlay {
                Capsule().strokeBorder(isRecording ? Color.dsAccent : .clear, lineWidth: 1)
            }
            .contentShape(.capsule)
            .dsHitTarget(SettingsMetrics.controlHeight)
        }
        .buttonStyle(.plain)
        .disabled(editor.registry.isLocked)
        .focusable(isRecording && !PlatformKeyRecorder.capturesBeforeMenus)
        .focused($isFocused)
        // iPadOS: no hook ahead of the key commands, so the focused pill takes the press.
        .onKeyPress(phases: .down) { press in
            guard isRecording, !PlatformKeyRecorder.capturesBeforeMenus else { return .ignored }
            editor.press(KeyShortcut(press))
            return .handled
        }
        .onChange(of: isRecording) { _, recording in
            isFocused = recording && !PlatformKeyRecorder.capturesBeforeMenus
        }
        .accessibilityLabel("\(command.title) shortcut")
        .accessibilityValue(isRecording ? "Recording" : shortcut?.displayString ?? "None")
        .accessibilityHint(isRecording ? "Type the new shortcut, or Escape to cancel" : "Records a new shortcut")
    }
}
