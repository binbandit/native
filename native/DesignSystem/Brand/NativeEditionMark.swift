import SwiftUI

/// The emblem in one edition, without the wordmark: what `NativeLockup` draws above "Native", and
/// what previews of an edition show. Lays out exactly like `NativeMark`; decorated editions reach
/// outside that frame without affecting layout.
public struct NativeEditionMark: View {
    let style: NativeMarkStyle

    public init(style: NativeMarkStyle) {
        self.style = style
    }

    public var body: some View {
        switch style {
        case .standard: NativeMark().fill()
        case .beta: NativeBetaMark()
        case .halloween(let edition): NativeHalloweenMark(edition: edition)
        case .diaDeMuertos(let edition): NativeMuertosMark(edition: edition)
        case .twoTone(let palette): NativeTwoToneMark(palette: palette)
        case .artwork(let artwork): NativeArtworkMark(artwork: artwork)
        }
    }
}

/// A celebration's icon images, standing in for the emblem. Equal by `id`, since images aren't.
public struct NativeEditionArtwork: Equatable, @unchecked Sendable {
    public let id: String
    public let light: Image
    public let dark: Image

    public init(id: String, light: Image, dark: Image) {
        self.id = id
        self.light = light
        self.dark = dark
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

/// An edition's icon in the emblem's frame: square, centered, and enlarged a little because icon
/// art keeps a transparent margin the emblem doesn't have.
private struct NativeArtworkMark: View {
    let artwork: NativeEditionArtwork

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .aspectRatio(NativeMark.aspectRatio, contentMode: .fit)
            .overlay {
                (colorScheme == .dark ? artwork.dark : artwork.light)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .scaleEffect(Self.marginCompensation)
            }
            .accessibilityElement()
            .accessibilityLabel("Native")
            .accessibilityAddTraits(.isImage)
    }

    private static let marginCompensation: CGFloat = 1.25
}
