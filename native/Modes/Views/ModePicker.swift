import Modes
import NativeCommands
import SwiftUI

/// The Mode pill's popover: every mode the task can be in, each with what it does in a line,
/// Native's first, then the user's own, then the project's. The current one is checked, and a mode
/// that can't do everything it asks on this agent says what it does instead. While the agent works
/// it says that a new mode's instructions go with the next message. The footer has the key that
/// steps to the next mode, and Edit Modes….
struct ModePicker: View {
    let control: TaskModeControl
    let dismiss: () -> Void

    @Environment(SettingsPresentation.self) private var settings: SettingsPresentation?

    var body: some View {
        let catalog = control.catalog
        let current = control.current.id
        VStack(alignment: .leading, spacing: 0) {
            caption(
                control.isWorking
                    ? "\(control.agentName) is working. A new mode's settings apply now, its instructions with your next message."
                    : "How \(control.agentName) works on this task")
            CappedHeightScrollView(maxHeight: ModeMetrics.pickerMaxHeight) {
                VStack(alignment: .leading, spacing: 0) {
                    rows(catalog.builtIn, current: current)
                    if !catalog.custom.isEmpty {
                        group("Your modes", catalog.custom, current: current)
                    }
                    if !catalog.project.isEmpty {
                        group(control.projectName.map { "From \($0)" } ?? "From the project", catalog.project, current: current)
                    }
                }
            }
            SeparatorLine()
                .padding(.top, DS.Space.xs)
            footer
        }
        .padding(.bottom, DS.Space.xs)
        .frame(width: ComposerMetrics.modelPickerWidth)
        .onAppear { control.refresh() }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.md)
            .padding(.bottom, DS.Space.xs)
    }

    private func group(_ title: String, _ modes: [Mode], current: Mode.ID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SeparatorLine()
                .padding(.top, DS.Space.xs)
            caption(title)
            rows(modes, current: current)
        }
    }

    private func rows(_ modes: [Mode], current: Mode.ID) -> some View {
        VStack(spacing: 0) {
            ForEach(modes) { mode in
                ComposerPickerRow(
                    symbol: mode.symbol, title: mode.name, detail: mode.summary,
                    note: control.limits(of: mode).joined(separator: " ").nilIfEmpty,
                    trailing: mode.id == current ? .checked(dimmed: false) : .none, isEnabled: true
                ) {
                    control.select(mode.id)
                    dismiss()
                }
                .help(mode.label)
            }
        }
        .padding(.horizontal, DS.Space.xs)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            Text("Next mode")
            if let shortcut = CommandRegistry.shared.shortcut(for: .sessionNextMode) {
                Kbd(shortcut.displayString)
            }
            Spacer()
            if let settings {
                Button("Edit Modes…") {
                    dismiss()
                    settings.open(.modes)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.dsTextSecondary)
                .dsHitTarget(DS.Size.controlXS)
            }
        }
        .font(.dsCaption)
        .foregroundStyle(.dsTextTertiary)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
