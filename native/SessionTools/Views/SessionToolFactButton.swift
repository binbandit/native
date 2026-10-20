import SwiftUI

/// One fact under the session's title: the tool's glyph and what it says, a wash on hover, and
/// selected while the tool is open. A click opens the tool, or does what it does.
struct SessionToolFactButton: View {
    let tool: SessionToolContribution
    let fact: SessionToolFact
    let isOpen: Bool
    /// Its menu, if the tool has one.
    var menu: AnyView?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if case .icon = fact.accessory {
                    SessionToolFactAccessory(accessory: fact.accessory)
                    Text(fact.text)
                } else {
                    Image(systemName: tool.systemImage)
                        .font(.dsMicro)
                    Text(fact.text)
                    SessionToolFactAccessory(accessory: fact.accessory)
                }
            }
            .lineLimit(1)
            .font(.dsCaption)
            .foregroundStyle(isOpen || isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.xs)
            .frame(height: DS.Size.statusGlyph + DS.Space.xs)
            .background(
                isOpen ? Color.dsSelected : isHovered ? Color.dsHover : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlXS)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .trackHover($isHovered)
        .contextMenu {
            if let menu { menu }
        }
        .help(isOpen ? "Close \(tool.title)" : tool.title)
        .accessibilityLabel("\(tool.title): \(fact.text)")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}
