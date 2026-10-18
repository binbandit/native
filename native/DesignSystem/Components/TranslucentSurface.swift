import SwiftUI

// The translucent surfaces outside the sidebar: overlays (popovers, toasts, drag previews) and the
// glass of floating controls. Each follows `\.dsTransparency`, so feature views use these instead
// of materials, `.glassEffect` or `.buttonStyle(.glass)` directly.

extension View {
    /// The backdrop of something floating over the window's content: toasts, drag previews,
    /// hand-built menus. The overlay color over a blur of what's beneath, as opaque as the
    /// user's transparency allows.
    public func dsOverlayBackground(in shape: some Shape) -> some View {
        background {
            OverlayBackdrop(blursDesktop: false)
                .clipShape(shape)
        }
    }

    /// The background of a popover, so it follows the user's transparency. Put it on the popover's
    /// content, in place of `.presentationBackground`.
    public func dsPopoverBackground() -> some View {
        presentationBackground {
            // A popover is its own window on the Mac: its blur has to sample behind that window.
            OverlayBackdrop(blursDesktop: true)
        }
    }

    /// Liquid Glass behind a floating control (the composer), or the opaque surface when the user
    /// turns transparency off. Control layer only, never content.
    public func dsGlassEffect(in shape: some Shape) -> some View {
        modifier(GlassBackground(shape: shape))
    }

    /// The glass button style for a control floating over content (jump to latest), following the
    /// user's transparency; at Solid it's an outlined overlay-colored capsule.
    public func dsGlassButtonStyle() -> some View {
        modifier(GlassButtonStyleModifier())
    }
}

private struct OverlayBackdrop: View {
    let blursDesktop: Bool

    @Environment(\.dsTransparency) private var transparency

    var body: some View {
        ZStack {
            if transparency != .solid {
                material
            }
            Rectangle()
                .fill(.dsOverlay)
                .opacity(transparency.overlayTint)
        }
    }

    @ViewBuilder private var material: some View {
        #if canImport(AppKit)
        if blursDesktop {
            DSBehindWindowMaterial(material: .popover)
        } else {
            Rectangle().fill(.regularMaterial)
        }
        #else
        Rectangle().fill(.regularMaterial)
        #endif
    }
}

private struct GlassBackground<GlassShape: Shape>: ViewModifier {
    let shape: GlassShape

    @Environment(\.dsTransparency) private var transparency

    func body(content: Content) -> some View {
        if let glass = transparency.controlGlass {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(.dsSurface, in: shape)
                .dsShadow(.floating)
        }
    }
}

private struct GlassButtonStyleModifier: ViewModifier {
    @Environment(\.dsTransparency) private var transparency

    func body(content: Content) -> some View {
        if let glass = transparency.controlGlass {
            content.buttonStyle(.glass(glass))
        } else {
            content.buttonStyle(SolidFloatingButtonStyle())
        }
    }
}

/// `.glass` without the glass: the same capsule, on the opaque overlay color.
private struct SolidFloatingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .dsTextPrimary : .dsTextQuaternary)
            .padding(DS.Space.sm)
            .background {
                Capsule().fill(.dsOverlay)
                Capsule().fill(configuration.isPressed ? .dsPressed : .clear)
            }
            .overlay { Capsule().strokeBorder(.dsBorder, lineWidth: 1) }
            .contentShape(Capsule())
            .dsShadow(.floating)
    }
}

#Preview("Translucent surfaces") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ForEach(DSTransparency.allCases) { level in
                HStack(spacing: DS.Space.lg) {
                    Text(level.title)
                        .font(.dsCallout)
                        .padding(DS.Space.md)
                        .dsOverlayBackground(in: .rect(cornerRadius: DS.Radius.card))
                    Text("Composer")
                        .font(.dsCallout)
                        .padding(DS.Space.md)
                        .dsGlassEffect(in: .rect(cornerRadius: DS.Radius.control))
                    Button {
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .dsGlassButtonStyle()
                }
                .dsTransparency(level)
            }
        }
        .padding(DS.Space.xl)
        .background(.dsAccentSubtle)
    }
}
