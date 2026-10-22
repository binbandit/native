import Experiments
import SwiftUI

/// One experiment in Labs: its title and stage, what it does, what it changes, and the control for its tier.
struct LabsExperimentRow: View {
    let id: SettingsRowID
    let experiment: ExperimentDescriptor
    let value: StoredValue
    let needsRelaunch: Bool
    let conflict: ExtensionConflict?
    let onChange: (StoredValue?) -> Void

    var body: some View {
        SettingsRow(
            id: id,
            title: Text(experiment.title),
            description: Text(experiment.summary),
            detail: detail,
            accessory: { SettingsBadge(experiment.stage.title) },
            control: { control }
        )
    }

    @ViewBuilder private var control: some View {
        switch experiment.tier {
        case .gate, .variant:
            SettingsSwitch(experiment.title, isOn: Binding(get: { value == .bool(true) }, set: { onChange(.bool($0)) }))
        case .parameter(let spec):
            switch spec.input {
            case .options(let options):
                SettingsSelect(
                    label: experiment.title,
                    selection: Binding(get: { value }, set: { onChange($0) }),
                    options: options.map { .init(value: $0.value, title: $0.title) }
                )
            case .text(let placeholder):
                LabsTextField(
                    label: experiment.title,
                    placeholder: placeholder,
                    text: Binding(
                        get: { if case .string(let text) = value { text } else { "" } },
                        set: { onChange(.string($0)) }
                    )
                )
            }
        }
    }

    /// What changes for the user, followed by anything they need to act on.
    private var detail: Text {
        let touches = experiment.touches.map(\.title).formatted(.list(type: .and))
        var lines = [Text("Changes \(touches)")]
        if experiment.requiresRelaunch {
            lines.append(
                needsRelaunch
                    ? Text("Takes effect the next time Native opens.").foregroundStyle(.dsAttention)
                    : Text("Changes take effect the next time Native opens.")
            )
        }
        if let conflict {
            lines.append(
                Text("Another experiment also changes \(conflict.pointTitle), so neither is in effect.")
                    .foregroundStyle(.dsDanger)
            )
        }
        return lines.dropFirst().reduce(lines[0]) { Text("\($0)\n\($1)") }
    }
}

/// A text parameter's field, outlined like the other settings inputs.
private struct LabsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        TextField(label, text: $text, prompt: Text(placeholder))
            .textFieldStyle(.plain)
            .labelsHidden()
            .settingsText(.body)
            .padding(.horizontal, DS.Space.lg)
            .frame(width: SettingsMetrics.selectWidth * 1.5, height: SettingsMetrics.controlHeight)
            .background(.dsBackground, in: shape)
            .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Labs experiment rows") {
    let experiments = ExperimentCatalog.native.experiments
    DSPreviewPair {
        SettingsRowGroup {
            ForEach(Array(experiments.enumerated()), id: \.element.id) { index, experiment in
                LabsExperimentRow(
                    id: LabsSettingsPage.rowID(experiment.id), experiment: experiment, value: experiment.defaultValue,
                    needsRelaunch: index == 0, conflict: index == 1 ? LabsPreviewFixtures.conflict : nil,
                    onChange: { _ in })
            }
        }
        .settingsPreviewPage()
    }
}
#endif
