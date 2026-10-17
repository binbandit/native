import Experiments
import SwiftUI

/// One experiment in Labs: its title and stage, what it does, what it changes, who owns it and
/// when it's due for review, and the control for its tier.
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

    /// "Changes Transcript style · Owned by transcript · Review by Jan 31, 2027", then a line for each
    /// thing that needs attention.
    private var detail: Text {
        let touches = experiment.touches.map(\.title).formatted(.list(type: .and))
        var lines = [Text("Changes \(touches) · Owned by \(experiment.owner) · \(review)")]
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

    private var review: Text {
        guard let date = experiment.reviewBy.date() else { return Text(verbatim: "") }
        let day = date.formatted(date: .abbreviated, time: .omitted)
        return experiment.reviewBy.isDue(at: .now)
            ? Text("Due for review since \(day)").foregroundStyle(.dsAttention)
            : Text("Review by \(day)")
    }
}

/// A text parameter's field, outlined like Conductor's settings inputs.
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
