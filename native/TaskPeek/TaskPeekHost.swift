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
    private var presented: TaskPeekPresentation.Request? {
        model.offersTaskPeek && !model.taskPeek.showsAttentionList ? model.taskPeek.request : nil
    }

    func body(content: Content) -> some View {
        content
            .environment(\.legacyAskShortcutEnabled, model.legacyAskShortcutEnabled(in: .shared))
            .simultaneousGesture(
                TapGesture().onEnded { model.closeTaskPeek(restoringSidebarFocus: false) },
                including: presented == nil ? .subviews : .all
            )
            .overlayPreferenceValue(TaskPeekAnchors.self) { anchors in
                GeometryReader { geometry in
                    if let request = presented {
                        card(request, anchors: anchors, geometry: geometry)
                    }
                }
                .animation(reduceMotion ? nil : .dsQuick, value: presented?.id)
            }
    }

    private func card(
        _ request: TaskPeekPresentation.Request, anchors: [SessionKey: Anchor<CGRect>], geometry: GeometryProxy
    ) -> some View {
        let bounds = CGRect(origin: .zero, size: geometry.size)
        let anchor = anchors[request.task].map { geometry[$0] }.flatMap { rect -> CGRect? in
            let clipped = rect.intersection(bounds)
            return clipped.isNull || clipped.isEmpty ? nil : clipped
        }
        // The identity covers the measurement observer and its state, so a new request gets an
        // initial measurement even when its rendered size matches the previous request.
        return TaskPeekCard(request: request, anchor: anchor, bounds: bounds) { key in
            settings.close(); model.openPeekedTask(key)
        }
        .id(request.id)
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
