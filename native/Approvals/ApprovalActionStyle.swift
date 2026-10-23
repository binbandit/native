import SwiftUI

struct ApprovalActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var primary = false
    var small = false
    var sweepProgress: Double?
    var pressing: ((Bool) -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? DS.Approval.smallButtonFont : .dsBodyMedium)
            .foregroundStyle(primary ? Color.dsTextOnAccent : .dsTextPrimary)
            .padding(.horizontal, small ? DS.Approval.smallButtonInset : DS.Approval.buttonInset)
            .frame(minHeight: small ? DS.Approval.smallButtonHeight : DS.Approval.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .fill(primary ? Color.dsAccent : DS.Approval.buttonFill(colorScheme))
                    .overlay(alignment: .leading) {
                        if let sweepProgress {
                            GeometryReader { geometry in
                                Rectangle().fill(.dsTextOnAccent.opacity(DS.Approval.sweepOpacity))
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
                        .strokeBorder(DS.Approval.buttonBorder(colorScheme), lineWidth: DS.Approval.rule)
                }
            }
            .opacity(configuration.isPressed ? DS.Approval.pressedOpacity : 1)
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
        }.padding(DS.Space.xl)
    }
}
#endif
