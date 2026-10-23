import SwiftUI

struct ApprovalActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var primary = false
    var pressing: ((Bool) -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBodyMedium)
            .foregroundStyle(primary ? Color.dsTextOnAccent : .dsTextPrimary)
            .padding(.horizontal, DS.Approval.buttonInset)
            .frame(minHeight: DS.Approval.buttonHeight)
            .background(
                primary ? Color.dsAccent : DS.Approval.buttonFill(colorScheme),
                in: .rect(cornerRadius: DS.Radius.control)
            )
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(DS.Approval.buttonBorder(colorScheme), lineWidth: DS.Approval.rule)
                }
            }
            .opacity(configuration.isPressed ? DS.Approval.pressedOpacity : 1)
            .onChange(of: configuration.isPressed) { _, pressed in pressing?(pressed) }
            .dsHitTarget(DS.Approval.buttonHeight)
    }
}

#if DEBUG
#Preview("Approval actions") {
    DSPreviewPair {
        HStack {
            Button("Don't Allow") {}.buttonStyle(ApprovalActionStyle())
            Button("Allow") {}.buttonStyle(ApprovalActionStyle(primary: true))
        }.padding(DS.Space.xl)
    }
}
#endif
