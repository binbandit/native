import SwiftUI

/// An agent's icon, sized to sit beside its name: the installed app's icon, its registry glyph in
/// the surrounding text color, or a monogram. Every place that shows an agent draws it with this
/// (menus, which only take an `Image`, use `AgentIconStore.image(for:size:scale:)`).
struct AgentIcon: View {
    let agent: AgentDefinition
    /// The square the icon occupies, like an SF Symbol's frame: `DS.Size.rowLeading` beside body
    /// text.
    var size: CGFloat = DS.Size.rowLeading

    @Environment(\.agentIconStore) private var injectedStore

    private var store: AgentIconStore {
        injectedStore ?? .shared
    }

    var body: some View {
        AgentIconArtworkView(artwork: store.artwork(for: agent), size: size)
            .task(id: agent.id) { await store.resolve(agent) }
            // The agent's name always sits beside it, or labels the control it's in.
            .accessibilityHidden(true)
    }
}

/// Draws an artwork in a `size` square. Each kind is inset to the same optical size, so an app
/// icon, a glyph and a monogram line up in a row and against text.
struct AgentIconArtworkView: View {
    let artwork: AgentIconArtwork
    let size: CGFloat

    var body: some View {
        Group {
            switch artwork {
            case .picture(let image):
                // App icons carry their own margin and shadow; they fill the square.
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            case .glyph(let glyph):
                AgentIconGlyphView(glyph: glyph)
                    .padding(size * Self.glyphInset)
            case .monogram(let letter):
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(.foreground.opacity(0.14))
                    .overlay {
                        Text(letter)
                            .font(.ds(size * 0.58, weight: .semibold))
                            .minimumScaleFactor(0.5)
                    }
                    .padding(size * Self.monogramInset)
            }
        }
        .frame(width: size, height: size)
    }

    /// Registry glyphs already leave a pixel of their 16 free; this brings them to an SF Symbol's
    /// weight beside text.
    private static let glyphInset: CGFloat = 0.0625
    /// Matches the visible body of a macOS app icon, which is about 80% of its square.
    private static let monogramInset: CGFloat = 0.09
}

/// A glyph scaled to fit, each piece filled in the foreground style with its own fill rule.
struct AgentIconGlyphView: View {
    let glyph: AgentIconGlyph

    var body: some View {
        Canvas { context, size in
            let box = glyph.viewBox
            let scale = min(size.width / box.width, size.height / box.height)
            let transform = CGAffineTransform(translationX: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -box.minX, y: -box.minY)
            for piece in glyph.pieces {
                var layer = context
                layer.opacity = piece.opacity
                layer.fill(Path(piece.path).applying(transform), with: .foreground, style: FillStyle(eoFill: piece.evenOdd))
            }
        }
    }
}
