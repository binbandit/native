import SwiftUI

/// Keep the signal with history as one toolbar group so the system cannot overflow it separately.
struct RootHistoryToolbar: View {
    let sidebarHidden: Bool
    let contentSize: CGSize
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: DS.Space.md) {
            HistoryNavigationButtons(
                canGoBack: model.canGoBack, canGoForward: model.canGoForward,
                onBack: model.goBack, onForward: model.goForward)
            if sidebarHidden, model.offersTaskPeek, !model.tasksNeedingAttention.isEmpty {
                TaskAttentionToolbarButton(
                    maxWidth: max(0, contentSize.width - DS.Peek.windowInset * 2),
                    maxBodyHeight: max(
                        DS.Peek.headerHeight,
                        contentSize.height - DS.Peek.headerHeight - DS.Peek.windowInset * 2))
            }
        }
        .fixedSize()
    }
}

#if DEBUG
#Preview("Collapsed navigation - Asks, failure and quiet") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ForEach(["collapsed", "collapsed-single", "collapsed-failure", "collapsed-empty"], id: \.self) { state in
                let app = SidebarDesignFixture.makeApp(state)
                RootHistoryToolbar(sidebarHidden: true, contentSize: CGSize(width: 1440, height: 900))
                    .environment(app)
            }
        }
    }
    .environment(SettingsPresentation())
}
#endif
