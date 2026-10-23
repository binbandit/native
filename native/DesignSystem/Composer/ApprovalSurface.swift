import SwiftUI

/// The quiet glass backing for an approval's dense annotations. A tinted material keeps the
/// command readable without the bright vibrancy intended for the ordinary composer's controls.
struct ApprovalSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsTransparency) private var transparency
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control)
        content
            .background {
                if transparency == .solid || reduceTransparency {
                    shape.fill(DS.Approval.surface(colorScheme))
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(DS.Approval.surface(colorScheme).opacity(DS.Approval.surfaceTintOpacity))
                        }
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(DS.Approval.edge(colorScheme), lineWidth: DS.Approval.rule) }
            .shadow(
                color: DS.Approval.shadow(colorScheme), radius: DS.Approval.shadowRadius,
                y: DS.Approval.shadowOffset
            )
            .environment(\.dsOnGlass, false)
    }
}

#if DEBUG
#Preview("Approval surface") {
    DSPreviewPair {
        ApprovalSurface {
            Text("Review the command before allowing it.").font(.dsBody).padding(DS.Approval.inset)
        }.padding(DS.Space.xl)
    }
}
#endif
