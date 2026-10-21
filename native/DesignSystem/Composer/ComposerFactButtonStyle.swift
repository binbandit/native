import SwiftUI

/// A setting written as a word in the composer. Hover and press change the ink, with no pill chrome.
public struct ComposerFactButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ComposerFactButtonBody(configuration: configuration)
    }
}

private struct ComposerFactButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.dsBody)
            .foregroundStyle(
                !isEnabled ? .dsTextTertiary : isHovered || configuration.isPressed ? .dsTextPrimary : .dsTextSecondary
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(
                minWidth: max(DS.Size.controlXS, DS.Size.minimumHitTarget),
                minHeight: max(DS.Size.controlXS, DS.Size.minimumHitTarget)
            )
            .contentShape(.rect)
            .dsFocusShape(.rect(cornerRadius: DS.Radius.control))
            .trackHover($isHovered)
    }
}

#if DEBUG
#Preview("Composer facts - Available and disabled") {
    DSPreviewPair {
        HStack(spacing: DS.Space.sm) {
            Button("6.1 Sol") {}.buttonStyle(ComposerFactButtonStyle())
            Text("·").foregroundStyle(.dsTextTertiary)
            Button("Low effort") {}.buttonStyle(ComposerFactButtonStyle())
            Button("Build") {}.buttonStyle(ComposerFactButtonStyle()).disabled(true)
        }
    }
}
#endif
