import SwiftUI

extension View {
    /// Shows one of the Compose page's address popovers (project, agent, device) under this control.
    ///
    /// They're drawn in the page rather than as system popovers, which center on their control and
    /// so cover the labels beside it: this one starts just left of the control's text, with its arrow
    /// near the text's start, and scrolls with the page. The page closes it on a click elsewhere or
    /// Escape (`ComposeTaskPage`), and lifts the control's line above the lines after it.
    func composeAddressPopover(
        isPresented: Bool, dismiss: @escaping () -> Void, @ViewBuilder content: @escaping (CGFloat) -> some View
    ) -> some View {
        modifier(ComposeAddressPopover(isPresented: isPresented, dismiss: dismiss, panel: content))
    }
}

extension View {
    /// The highlight behind an address control while its popover is open, reaching a little past
    /// its text so the text stays put.
    func composeFocus(_ isOpen: Bool, height: CGFloat = DS.ComposeTask.focusHeight) -> some View {
        background {
            if isOpen {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(.dsSelected)
                    .padding(.horizontal, -DS.ComposeTask.focusInset)
                    .frame(height: height)
            }
        }
    }
}

/// A held letter keeps its ink while its controls stop accepting actions.
struct ComposeAddressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The Compose page's visible area, which an address popover measures its room against.
    nonisolated static var composeViewport: Self { .named("composeViewport") }
}

extension EnvironmentValues {
    @Entry var composeViewportHeight: CGFloat = .infinity
}

private struct ComposeAddressPopover<Panel: View>: ViewModifier {
    let isPresented: Bool
    let dismiss: () -> Void
    let panel: (CGFloat) -> Panel

    @Environment(\.composeViewportHeight) private var viewportHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The control's frame in the visible page.
    @State private var control = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .composeViewport)
            } action: {
                control = $0
            }
            .overlay(alignment: .topLeading) {
                if isPresented {
                    let shape = ComposeAddressPopoverShape()
                    panel(maxHeight)
                        .padding(.top, DS.ComposeTask.popoverArrowHeight)
                        .dsOverlayBackground(in: shape)
                        .clipShape(shape)
                        .overlay { shape.stroke(.dsBorder, lineWidth: 1) }
                        .dsShadow(.modal)
                        .fixedSize()
                        // Its top the gap below the row, with the arrow rising into that gap.
                        .offset(
                            x: -DS.ComposeTask.popoverLeading,
                            y: control.height + DS.ComposeTask.popoverGap - DS.ComposeTask.popoverArrowHeight
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape, dismiss)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .dsPopover, value: isPresented)
    }

    /// The room left below the control in the visible page, so a long popover scrolls inside itself
    /// rather than running off the bottom of the window.
    private var maxHeight: CGFloat {
        let room = viewportHeight - control.maxY - DS.ComposeTask.popoverGap - DS.Space.lg
        return max(min(room, DS.ComposeTask.popoverMaxHeight), DS.ComposeTask.popoverMinHeight)
    }
}

/// A popover's outline: a rounded rectangle with the arrow rising from its top edge.
private nonisolated struct ComposeAddressPopoverShape: Shape {
    func path(in rect: CGRect) -> Path {
        // One outline, so the border runs up and over the arrow instead of across its base.
        let top = rect.minY + DS.ComposeTask.popoverArrowHeight
        let radius = DS.Radius.card
        let tip = rect.minX + DS.ComposeTask.popoverArrowTip
        let halfWidth = DS.ComposeTask.popoverArrowWidth / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: top))
        path.addLine(to: CGPoint(x: tip - halfWidth, y: top))
        path.addLine(to: CGPoint(x: tip, y: rect.minY))
        path.addLine(to: CGPoint(x: tip + halfWidth, y: top))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
            radius: radius)
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
            radius: radius)
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: top),
            radius: radius)
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.maxX, y: top), radius: radius)
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview("Compose - Address popover") {
    DSPreviewPair {
        Text("Codex 6.1 Sol").font(.dsCallout)
            .frame(height: DS.ComposeTask.rowHeight)
            .composeAddressPopover(isPresented: true, dismiss: {}) { _ in
                Text("Agent, model, effort and when it asks").font(.dsBody).padding(DS.Space.lg)
                    .frame(width: DS.ComposeTask.popoverWidth, alignment: .leading)
            }
            .frame(width: 480, height: 200, alignment: .topLeading)
            .padding(DS.Space.xxl)
    }
}
#endif
