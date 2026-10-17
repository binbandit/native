import SwiftUI

/// One process tree in the table: a row with its name, trend and totals that expands to show each
/// process, indented under its parent.
struct ResourceGroupRows: View {
    let group: ProcessGroup
    let history: [UInt64]
    @Binding var isExpanded: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.dsDisclosure) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 0) {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: StatusBarMetrics.glyph * 0.8, weight: .semibold))
                            .foregroundStyle(.dsTextTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(group.title.uppercased())
                            .font(.dsCaptionMedium)
                            .tracking(DS.Tracking.wide)
                            .foregroundStyle(.dsTextPrimary)
                        Text("\(group.processes.count)")
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                        Spacer(minLength: DS.Space.md)
                        Sparkline(values: history)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    figures(cpu: group.cpu, memory: group.memory, isPrimary: true)
                }
                .padding(.horizontal, DS.Space.lg)
                .frame(height: DS.Size.listRow)
                .background(isHovered ? Color.dsHover : .clear)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .trackHover($isHovered)
            .help(isExpanded ? "Hide \(group.title)'s processes" : "Show \(group.title)'s processes")
            .accessibilityLabel(group.title)
            .accessibilityValue("\(group.processes.count) processes, \(DSFormat.memory(group.memory)), \(DSFormat.cpu(group.cpu)) CPU")
            .accessibilityHint(isExpanded ? "Hides its processes" : "Shows its processes")

            if isExpanded {
                ForEach(group.processes) { process in
                    processRow(process)
                }
            }
        }
    }

    private func processRow(_ process: ProcessUsage) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                Text(process.name)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(process.pid, format: .number.grouping(.never))")
                    .font(.dsMonoMicro)
                    .foregroundStyle(.dsTextQuaternary)
            }
            // Under the chevron, then a step per level of the tree.
            .padding(.leading, DS.Space.lg + CGFloat(process.depth) * StatusBarMetrics.indent)
            .frame(maxWidth: .infinity, alignment: .leading)
            figures(cpu: process.cpu, memory: process.memory, isPrimary: false)
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.controlXS)
        .help("\(process.name), process \(process.pid)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(process.name)
        .accessibilityValue("Process \(process.pid), \(DSFormat.memory(process.memory)), \(process.cpu.map(DSFormat.cpu) ?? "measuring") CPU")
    }

    private func figures(cpu: Double?, memory: UInt64, isPrimary: Bool) -> some View {
        HStack(spacing: 0) {
            Text(cpu.map(DSFormat.cpu) ?? "–")
                .frame(width: StatusBarMetrics.cpuColumn, alignment: .trailing)
            Text(DSFormat.memory(memory))
                .frame(width: StatusBarMetrics.memoryColumn, alignment: .trailing)
        }
        .font(isPrimary ? .dsBody : .dsCaption)
        .monospacedDigit()
        .foregroundStyle(isPrimary ? .dsTextPrimary : .dsTextSecondary)
    }
}
