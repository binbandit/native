import SwiftUI

/// The agent picker's last row: Add Agent…, naming the agents Native knows but can't find on this
/// Mac, as the sidebar's New Session menu ends with it.
struct AgentPickerAddRow: View {
    let missingAgents: [String]
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "plus")
                    .font(.dsBody)
                    .foregroundStyle(isHighlighted ? .dsTextPrimary : .dsTextSecondary)
                    .frame(width: DS.Size.rowLeading)
                Text("Add Agent…")
                    .font(.dsCallout)
                    .foregroundStyle(.dsTextPrimary)
                    .fixedSize()
                Spacer(minLength: DS.Space.md)
                Text(summary)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: max(DS.Size.controlMD, DS.Size.minimumHitTarget))
            .background(
                isHighlighted ? Color.dsSelected : .clear,
                in: .rect(cornerRadius: DS.Radius.row, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("See how to install \(ListFormatter.localizedString(byJoining: missingAgents))")
        .accessibilityLabel("Add Agent")
        .accessibilityValue(summary)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }

    /// "Cursor isn't installed", "Cursor and Copilot aren't installed", "Cursor, Copilot and 2 more
    /// aren't installed".
    private var summary: String {
        let shown =
            missingAgents.count > 3
            ? Array(missingAgents.prefix(2)) + ["\(missingAgents.count - 2) more"] : missingAgents
        return
            "\(ListFormatter.localizedString(byJoining: shown)) \(missingAgents.count == 1 ? "isn't" : "aren't") installed"
    }
}
