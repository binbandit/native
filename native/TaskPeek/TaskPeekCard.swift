import SwiftUI

/// The measured card belongs to one request. Replacing that request replaces this view's identity,
/// including the geometry observer, rather than waiting for an equal-sized card to change size.
struct TaskPeekCard: View {
    let request: TaskPeekPresentation.Request
    let anchor: CGRect?
    let bounds: CGRect
    let openTask: (SessionKey) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measured: CGSize?

    var body: some View {
        let width = min(DS.Peek.width, bounds.width - DS.Peek.windowInset * 2)
        let frame = measured.map { TaskPeekFrame(anchor: anchor, size: $0, in: bounds) }
        let maxBodyHeight = min(
            DS.Peek.maxBodyHeight,
            max(
                DS.Peek.headerHeight,
                bounds.height - DS.Peek.toolbarGap - DS.Peek.windowInset - DS.Peek.headerHeight))
        ZStack(alignment: .topLeading) {
            TaskPeekView(request: request, maxBodyHeight: maxBodyHeight, openTask: openTask)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self, of: \.size) { measured = $0 }
                .frame(height: frame?.card.height, alignment: .top)
                .clipShape(.rect(cornerRadius: DS.Peek.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Peek.radius).strokeBorder(.dsOverlayEdge, lineWidth: 1)
                }
                .offset(x: frame?.card.minX ?? 0, y: frame?.card.minY ?? 0)
            if let arrow = frame?.arrow {
                let view = TaskPeekArrow(edge: arrow.edge)
                let center = view.center(for: arrow.base)
                view.offset(x: center.x - view.size.width / 2, y: center.y - view.size.height / 2)
            }
        }
        .compositingGroup()
        .dsShadow(.modal)
        .opacity(frame == nil ? 0 : 1)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { model.closeTaskPeek() }
    }
}

#if DEBUG
#Preview("Framed Peek - Routine and finished") {
    let app = SidebarDesignFixture.makeApp("plan")
    let bounds = CGRect(
        x: 0, y: 0, width: DS.Peek.width + DS.Peek.windowInset * 2,
        height: DS.Peek.maxBodyHeight + DS.Peek.headerHeight + DS.Peek.windowInset * 2)
    DSPreviewPair {
        VStack {
            ForEach([TaskPeekPreviewFixtures.State.routine, .finished], id: \.rawValue) { state in
                TaskPeekCard(request: TaskPeekPreviewFixtures.prepare(app, state: state), anchor: nil, bounds: bounds) {
                    app.openPeekedTask($0)
                }
                .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            }
        }
    }
    .environment(app)
}
#endif
