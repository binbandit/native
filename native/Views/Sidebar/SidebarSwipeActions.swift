import SwiftUI

/// An action a sidebar row reveals when swiped on a touch screen, the touch equivalent of its
/// hover buttons and context menu.
struct SidebarSwipeAction: Identifiable {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var id: String { title }

    init(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }
}

extension View {
    /// Swipe actions for a sidebar row on touch screens, as `List` rows have; the sidebar isn't a
    /// `List`, so it draws its own. Pointer platforms reach the same actions through the context
    /// menu and hover buttons, so this does nothing there.
    func sidebarSwipeActions(leading: [SidebarSwipeAction] = [], trailing: [SidebarSwipeAction] = []) -> some View {
        #if os(iOS)
        modifier(SidebarSwipeModifier(leading: leading, trailing: trailing))
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Reveals the actions under the row as it slides: a short swipe opens them, a long one runs the
/// first, and a tap anywhere on the row closes them again.
private struct SidebarSwipeModifier: ViewModifier {
    let leading: [SidebarSwipeAction]
    let trailing: [SidebarSwipeAction]

    @State private var offset: CGFloat = 0
    @State private var settled: CGFloat = 0
    @State private var width: CGFloat = 0

    /// Each revealed action is a touch target wide.
    private static let actionWidth = DS.Size.minimumHitTarget + DS.Space.lg

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background {
                HStack(spacing: 0) {
                    actions(leading)
                    Spacer(minLength: 0)
                    actions(trailing.reversed())
                }
                .clipShape(.rect(cornerRadius: DS.Radius.row, style: .continuous))
                .opacity(offset == 0 ? 0 : 1)
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: DS.Space.xl)
                    .onChanged { value in
                        // Vertical drags belong to the scroll view.
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        offset = clamp(settled + value.translation.width)
                    }
                    .onEnded { value in
                        settle(after: value.predictedEndTranslation.width + settled)
                    }
            )
            .simultaneousGesture(TapGesture().onEnded { close() }, including: settled == 0 ? .none : .all)
            .animation(.dsPanel, value: settled)
    }

    private func actions(_ actions: [SidebarSwipeAction]) -> some View {
        ForEach(actions) { action in
            Button {
                close()
                action.action()
            } label: {
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
                    .font(.dsCallout)
                    .foregroundStyle(.white)
                    .frame(width: Self.actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(action.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.title)
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        let maxLeading = leading.isEmpty ? 0 : width
        let maxTrailing = trailing.isEmpty ? 0 : width
        return min(max(value, -maxTrailing), maxLeading)
    }

    /// Opens, closes or, past most of the row's width, runs the outermost action.
    private func settle(after translation: CGFloat) {
        let full = width * 0.6
        if translation > full, let first = leading.first {
            close()
            first.action()
        } else if translation < -full, let first = trailing.first {
            close()
            first.action()
        } else if translation > Self.actionWidth / 2, !leading.isEmpty {
            open(to: CGFloat(leading.count) * Self.actionWidth)
        } else if translation < -Self.actionWidth / 2, !trailing.isEmpty {
            open(to: -CGFloat(trailing.count) * Self.actionWidth)
        } else {
            close()
        }
    }

    private func open(to value: CGFloat) {
        withAnimation(.dsPanel) {
            settled = value
            offset = value
        }
    }

    private func close() {
        withAnimation(.dsPanel) {
            settled = 0
            offset = 0
        }
    }
}
#endif
