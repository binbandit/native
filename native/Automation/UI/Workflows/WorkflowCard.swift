import SwiftUI

/// A workflow in the picker, after Conductor's suggested routines: a round glyph, the name, what it
/// does, and its shape (steps, goals, gates). One a plugin got wrong says why it can't run.
struct WorkflowCard: View {
    let entry: WorkflowLibrary.Entry
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: entry.definition.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected || isHovered ? .dsTextPrimary : .dsTextSecondary)
                    .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                    .background(.dsSurfaceSunken, in: .circle)
                    .overlay { Circle().strokeBorder(.dsSeparator, lineWidth: 1) }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(entry.definition.name)
                        .font(.dsCalloutMedium)
                        .foregroundStyle(.dsTextPrimary)
                    Text(entry.definition.summary)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .lineLimit(3, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                    footer
                        .padding(.top, DS.Space.sm)
                }
                .tracking(DS.Tracking.tight)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(isSelected ? Color.dsAccent : .dsSeparator, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!entry.isRunnable)
        .opacity(entry.isRunnable ? 1 : 0.6)
        .trackHover($isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(entry.isRunnable ? entry.definition.summary : entry.issues.map(\.description).joined(separator: "\n"))
    }

    private var fill: Color {
        isSelected ? .dsAccentSubtle : isHovered ? .dsHover : .dsSurface
    }

    @ViewBuilder private var footer: some View {
        if let issue = entry.issues.first {
            Label(issue.description, systemImage: "exclamationmark.triangle")
                .font(.dsCaption)
                .foregroundStyle(.dsDanger)
                .lineLimit(2)
        } else {
            let steps = entry.definition.steps
            let parts = [
                "\(steps.count) steps",
                steps.contains { $0.goal != nil } ? "goals" : nil,
                steps.count(where: { $0.approval != nil }).nonZero.map { "\($0) \($0 == 1 ? "approval" : "approvals")" },
                steps.contains { $0.kind == .pullRequest } ? "pull request" : nil,
            ]
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10))
                Text(parts.compactMap(\.self).joined(separator: " · "))
                if case .plugin(let plugin) = entry.source {
                    Text("· \(plugin)")
                }
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .lineLimit(1)
        }
    }
}

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}
