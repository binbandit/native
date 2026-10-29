import Git
import NativeCommands
import SwiftUI

/// The start field's address: Quick Entry's "to … on … from …" and its pickers, in a popover.
struct HomeNextStartAddress: View {
    let model: AppModel
    @Bindable var entry: QuickEntryModel
    @Environment(GitStore.self) private var git: GitStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskAddressLine(
                agent: model.quickEntryRuntime?.agent.displayName ?? "Choose agent",
                model: model.quickEntryModelName,
                device: model.deviceName(entry.device),
                deviceLook: HostLookStore.shared.look(for: entry.device, named: model.deviceName(entry.device)),
                project: entry.project.flatMap(model.projects.project)?.name ?? "No project",
                branch: branch, isCompact: true,
                picker: entry.picker, choose: entry.toggle
            )
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.ComposerSettings.popoverInset)
            if entry.picker != nil {
                SeparatorLine()
                QuickEntryPicker(model: model, entry: entry)
            }
            if model.quickEntry.isEnabled {
                SeparatorLine()
                Button {
                    model.expandQuickEntry()
                } label: {
                    HStack(spacing: DS.Space.md) {
                        Text("Write on the New Task Page")
                        Spacer(minLength: DS.Space.md)
                        if let shortcut = CommandRegistry.shared.keyboardShortcut(for: .taskCompose) {
                            Kbd(shortcut)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.ComposerSettings.rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.ComposerSettings.popoverInset)
            }
        }
        .frame(width: DS.ComposerSettings.popoverWidth)
    }

    private var branch: String? {
        guard entry.device == .thisMac, let project = entry.project.flatMap(model.projects.project) else { return nil }
        return git?.model(for: project.url).branch?.name
    }
}
