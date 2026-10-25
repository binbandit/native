import SwiftUI

/// A single presenter lets any surface open Peek. Visible sidebar rows and Home's rows contribute
/// their anchor; Settings and filtered or collapsed lists fall back to the top of the content.
nonisolated struct TaskPeekAnchors: PreferenceKey {
    static var defaultValue: [SessionKey: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [SessionKey: Anchor<CGRect>], nextValue: () -> [SessionKey: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { first, _ in first })
    }
}

/// Peek is drawn in the window rather than as a system popover, so it can hang from its row the
/// way the sidebar draws it and never rise over the toolbar (`TaskPeekFrame`). A click anywhere
/// outside it closes it and still lands, as a transient popover's does; Escape and Open Task close it
/// from inside.
private struct TaskPeekHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Peek's size at its width, measured once it's laid out; nil until then, so it never shows in
    /// the wrong place for a frame.
    @State private var measured: CGSize?

    private var presented: TaskPeekPresentation.Request? {
        model.offersTaskPeek && !model.taskPeek.showsAttentionList ? model.taskPeek.request : nil
    }

    func body(content: Content) -> some View {
        content
            .environment(\.legacyAskShortcutEnabled, model.legacyAskShortcutEnabled(in: .shared))
            .simultaneousGesture(
                TapGesture().onEnded { model.closeTaskPeek() }, including: presented == nil ? .subviews : .all
            )
            .overlayPreferenceValue(TaskPeekAnchors.self) { anchors in
                GeometryReader { geometry in
                    if let request = presented {
                        card(request, anchors: anchors, geometry: geometry)
                    }
                }
                .animation(reduceMotion ? nil : .dsQuick, value: presented?.id)
            }
            .onChange(of: presented?.id) { measured = nil }
    }

    private func card(
        _ request: TaskPeekPresentation.Request, anchors: [SessionKey: Anchor<CGRect>], geometry: GeometryProxy
    ) -> some View {
        let bounds = CGRect(origin: .zero, size: geometry.size)
        let anchor = anchors[request.task].map { geometry[$0] }.flatMap { rect -> CGRect? in
            let clipped = rect.intersection(bounds)
            return clipped.isNull || clipped.isEmpty ? nil : clipped
        }
        let width = min(DS.Peek.width, geometry.size.width - DS.Peek.windowInset * 2)
        let frame = measured.map { TaskPeekFrame(anchor: anchor, size: $0, in: bounds) }
        let maxBodyHeight = min(
            DS.Peek.maxBodyHeight,
            max(
                DS.Peek.headerHeight,
                geometry.size.height - DS.Peek.toolbarGap - DS.Peek.windowInset - DS.Peek.headerHeight))
        return ZStack(alignment: .topLeading) {
            TaskPeekView(
                request: request, maxBodyHeight: maxBodyHeight,
                openTask: { key in
                    settings.close(); model.openPeekedTask(key)
                }
            )
            .id(request.id)
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

extension View {
    func taskPeekHost() -> some View { modifier(TaskPeekHost()) }
    func taskPeekAnchor(_ key: SessionKey) -> some View {
        modifier(TaskPeekAnchor(key: key))
    }
}

private struct TaskPeekAnchor: ViewModifier {
    let key: SessionKey
    @Environment(\.offersTaskPeekAnchors) private var isOffered

    func body(content: Content) -> some View {
        content.anchorPreference(key: TaskPeekAnchors.self, value: .bounds) { isOffered ? [key: $0] : [:] }
    }
}

extension EnvironmentValues {
    /// Off where the rows aren't on screen (a collapsed sidebar), so Peek falls back to the top of
    /// the content.
    @Entry var offersTaskPeekAnchors = true
    @Entry var legacyAskShortcutEnabled = true
    @Entry var answerShortcutAskID: TaskPeekAsk.ID?
}
