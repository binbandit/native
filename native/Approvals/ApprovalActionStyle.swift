import SwiftUI

struct ApprovalActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var primary = false
    var small = false
    var acknowledgesCompletion = false
    var sweepProgress: Double?
    var pressing: ((Bool) -> Void)?

    private var isEmphasized: Bool { isEnabled || acknowledgesCompletion }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? DS.Approval.smallButtonFont : .dsBodyMedium)
            .foregroundStyle(isEmphasized ? (primary ? Color.dsTextOnAccent : .dsTextPrimary) : .dsTextTertiary)
            .padding(.horizontal, small ? DS.Approval.smallButtonInset : DS.Approval.buttonInset)
            .frame(minHeight: small ? DS.Approval.smallButtonHeight : DS.Approval.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .fill(isEmphasized ? (primary ? Color.dsAccent : DS.Approval.buttonFill(colorScheme)) : .dsSelected)
                    .overlay(alignment: .leading) {
                        if let sweepProgress {
                            GeometryReader { geometry in
                                Rectangle().fill(
                                    (primary ? Color.dsTextOnAccent : .dsTextPrimary).opacity(DS.Approval.sweepOpacity)
                                )
                                .frame(width: geometry.size.width * sweepProgress)
                            }
                            .clipShape(.rect(cornerRadius: DS.Radius.control))
                            .allowsHitTesting(false)
                        }
                    }
            }
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(
                            isEmphasized ? DS.Approval.buttonBorder(colorScheme) : .clear,
                            lineWidth: DS.Approval.rule)
                }
            }
            .opacity(isEnabled && configuration.isPressed ? DS.Approval.pressedOpacity : 1)
            .onChange(of: configuration.isPressed) { _, pressed in pressing?(pressed) }
            .dsHitTarget(small ? DS.Approval.smallButtonHeight : DS.Approval.buttonHeight)
    }
}

#if DEBUG
#Preview("Approval actions") {
    DSPreviewPair {
        HStack {
            Button("Don't Allow") {}.buttonStyle(ApprovalActionStyle())
            Button("Allow") {}.buttonStyle(ApprovalActionStyle(primary: true))
            Button("Unavailable") {}.buttonStyle(ApprovalActionStyle(primary: true)).disabled(true)
        }.padding(DS.Space.xl)
    }
}
#endif
