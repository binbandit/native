import SwiftUI

/// A bordered content surface (the reference app's card: surface fill, 1pt separator outline, 8pt radius).
/// It sets itself as the container shape, so nested `ConcentricRectangle`s round with it.
public struct Card<Content: View>: View {
    let padding: CGFloat
    let radius: CGFloat
    let content: Content

    public init(padding: CGFloat = DS.Space.lg, radius: CGFloat = DS.Radius.card, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.dsSurface, in: shape)
            .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
            .containerShape(shape)
    }
}

#Preview("Card") {
    DSPreviewPair {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Card").font(.dsHeadline).foregroundStyle(.dsTextPrimary)
                Text("Surface fill, 1pt separator outline, 8pt radius.").font(.dsBody).foregroundStyle(.dsTextSecondary)
            }
        }
        .frame(width: 280)
    }
}
