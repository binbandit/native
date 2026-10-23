import SwiftUI

/// The compact address shared by Quick Entry and, later, Compose and Home.
struct TaskAddressLine: View {
    let agent: String
    let model: String?
    let device: String
    let project: String
    let picker: QuickEntryModel.Picker?
    let choose: (QuickEntryModel.Picker) -> Void

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            preposition("to")
            address(.agent, title: agent, detail: model)
            preposition("on")
            address(.device, title: device)
            preposition("from")
            address(.project, title: project)
        }
        .font(.dsCallout)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Task address")
    }

    private func preposition(_ word: String) -> some View {
        Text(word)
            .foregroundStyle(.dsTextTertiary)
            .padding(.horizontal, DS.Space.xxs)
    }

    private func address(_ kind: QuickEntryModel.Picker, title: String, detail: String? = nil) -> some View {
        Button {
            choose(kind)
        } label: {
            HStack(spacing: DS.Space.sm) {
                Text(title)
                    .foregroundStyle(.dsTextPrimary)
                if let detail {
                    Text(detail)
                        .foregroundStyle(.dsTextSecondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.dsMicro)
                    .foregroundStyle(.dsTextTertiary)
            }
            .padding(.horizontal, DS.Space.sm)
            .frame(minHeight: DS.Size.controlSM)
            .background(picker == kind ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control))
        }
        .buttonStyle(.plain)
        .dsHitTarget(DS.Size.controlSM)
        .accessibilityLabel(kind == .agent ? "Choose agent" : kind == .device ? "Choose device" : "Choose project")
        .accessibilityValue([title, detail].compactMap(\.self).joined(separator: ", "))
    }
}

#if DEBUG
#Preview("Task address - Rest and device open") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            TaskAddressLine(agent: "Codex", model: "6.1 Sol", device: "This Mac", project: "native", picker: nil) { _ in
            }
            TaskAddressLine(agent: "Claude Code", model: "Opus 5.5", device: "elara", project: "pier", picker: .device)
            { _ in }
        }
        .padding(DS.Space.lg)
    }
}
#endif
