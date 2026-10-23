import SwiftUI

/// A single presenter lets any surface open Peek. Visible sidebar rows contribute their anchor;
/// Home, Settings and filtered or collapsed lists fall back to the window's top edge.
nonisolated struct TaskPeekAnchors: PreferenceKey {
    static var defaultValue: [SessionKey: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [SessionKey: Anchor<CGRect>], nextValue: () -> [SessionKey: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { first, _ in first })
    }
}

private struct TaskPeekHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings

    func body(content: Content) -> some View {
        content
            .environment(\.legacyAskShortcutEnabled, model.legacyAskShortcutEnabled(in: .shared))
            .overlayPreferenceValue(TaskPeekAnchors.self) { anchors in
                GeometryReader { geometry in
                    let anchor = model.taskPeek.request.flatMap { anchors[$0.task] }.map { geometry[$0] }
                    let visible = anchor.flatMap { rect -> CGRect? in
                        let clipped = rect.intersection(CGRect(origin: .zero, size: geometry.size))
                        return clipped.isNull || clipped.isEmpty ? nil : clipped
                    }
                    Color.clear
                        .frame(width: visible?.width ?? 0, height: visible?.height ?? 0)
                        .allowsHitTesting(false)
                        .popover(
                            item: Binding(
                                get: { model.offersTaskPeek ? model.taskPeek.request : nil },
                                set: { model.taskPeek.request = $0 }),
                            arrowEdge: visible == nil ? .top : .trailing
                        ) { request in
                            TaskPeekView(
                                request: request,
                                maxBodyHeight: min(
                                    DS.Peek.maxBodyHeight,
                                    max(
                                        DS.Peek.headerHeight,
                                        geometry.size.height - DS.Peek.headerHeight - DS.Peek.windowInset * 2)),
                                openTask: { key in
                                    settings.close(); model.openPeekedTask(key)
                                }
                            )
                            .frame(width: min(DS.Peek.width, geometry.size.width - DS.Peek.windowInset * 2))
                            .id(request.id)
                            .environment(model)
                            .presentationBackground(Color.dsOverlay)
                            .presentationCompactAdaptation(.popover)
                        }
                        .position(
                            x: visible?.midX ?? geometry.size.width / 2,
                            y: visible?.midY ?? DS.Peek.windowInset)
                }
            }
    }
}

extension View {
    func taskPeekHost() -> some View { modifier(TaskPeekHost()) }
    func taskPeekAnchor(_ key: SessionKey) -> some View {
        anchorPreference(key: TaskPeekAnchors.self, value: .bounds) { [key: $0] }
    }
}

extension EnvironmentValues {
    @Entry var legacyAskShortcutEnabled = true
    @Entry var oldestTaskAskID: TaskPeekAsk.ID?
}
