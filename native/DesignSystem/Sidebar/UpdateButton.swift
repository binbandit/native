import SwiftUI

/// Factory's update button: a small orange tag in the window's toolbar row, right of the sidebar
/// toggle. Black 13pt medium text on the accent, 2x10pt padding, 4pt radius; darker on hover and
/// press.
public struct UpdateButton: View {
    let version: String
    let action: () -> Void

    @State private var isHovered = false

    /// - Parameter version: The version the update installs, e.g. "1.4.0".
    public init(version: String, action: @escaping () -> Void) {
        self.version = version
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text("Update")
                .font(.ds(13, weight: .medium))
                .tracking(DS.Tracking.snug)
                .foregroundStyle(.dsTextOnAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, DS.Space.xxs)
                .dsHitTarget(20)
        }
        .buttonStyle(UpdateButtonStyle(isHovered: isHovered))
        .help("Update to version \(version). Click to download and restart.")
        .accessibilityLabel("Update Available")
        .accessibilityValue("Version \(version)")
        .trackHover($isHovered)
    }
}

private struct UpdateButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        configuration.label
            .background(configuration.isPressed ? .dsAccentPressed : isHovered ? .dsAccentHover : .dsAccent, in: shape)
            .dsFocusShape(shape)
    }
}

#Preview("Update button") {
    DSPreviewPair {
        UpdateButton(version: "1.4.0") {}
    }
}
