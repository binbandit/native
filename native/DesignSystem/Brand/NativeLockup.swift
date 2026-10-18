import SwiftUI

/// Native's logo: the `NativeMark` emblem with the "Native" wordmark, set in Geist semibold with
/// tight tracking. Both parts draw in the current foreground style.
///
///     NativeLockup(size: 28, layout: .stacked).foregroundStyle(.dsTextPrimary)
public struct NativeLockup: View {
    public enum Layout: Sendable {
        /// Emblem left of the wordmark, centered on its capitals: headers, about boxes.
        case horizontal
        /// Emblem above the wordmark: the home page, empty windows.
        case stacked
    }

    let size: CGFloat
    let layout: Layout
    let style: NativeMarkStyle

    /// - Parameter size: The wordmark's point size; the emblem and spacing scale with it.
    /// - Parameter style: The emblem's edition, to match the app icon the user has (Beta, a celebration).
    public init(size: CGFloat = 20, layout: Layout = .horizontal, style: NativeMarkStyle = .standard) {
        self.size = size
        self.layout = layout
        self.style = style
    }

    public var body: some View {
        Group {
            switch layout {
            case .horizontal:
                let capHeight = capHeight
                HStack(alignment: .firstTextBaseline, spacing: size * 0.4) {
                    mark(height: capHeight * 1.3)
                        // Center the emblem on the capitals rather than on the text's line box.
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + capHeight / 2 }
                    wordmark
                }
            case .stacked:
                VStack(spacing: size * 0.6) {
                    if case .artwork = style {
                        // An edition's icon tile carries the decorated marks' visual weight: the art
                        // keeps a transparent margin, so its square is larger than the emblem.
                        NativeEditionMark(style: style)
                            .frame(width: size * Self.artworkSide, height: size * Self.artworkSide)
                    } else {
                        mark(height: size * 2)
                    }
                    wordmark
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Native")
        .accessibilityAddTraits(.isImage)
    }

    private var wordmark: some View {
        Text("Native")
            .font(.ds(size, weight: .semibold))
            // Geist sets loose at display sizes; -2.5% closes it up without touching.
            .tracking(-0.025 * size)
            .fixedSize()
    }

    private func mark(height: CGFloat) -> some View {
        NativeEditionMark(style: style)
            .frame(width: height * NativeMark.aspectRatio, height: height)
    }

    /// The stacked lockup's icon tile, in wordmark sizes: about 104pt of visible tile on Home.
    private static let artworkSide: CGFloat = 4.6

    private var capHeight: CGFloat {
        DSTypography.platformFont(size: size, weight: .semibold).capHeight
    }
}

#Preview("Brand") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            NativeMark()
                .frame(width: 96, height: 62)
            NativeLockup(size: 13)
            NativeLockup(size: 22)
            NativeLockup(size: 28, layout: .stacked)
        }
        .foregroundStyle(.dsTextPrimary)
    }
}
