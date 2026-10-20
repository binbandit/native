import GitHub
import SwiftUI

extension View {
    /// Docks a pull request's private question panel beside its page while it's open: an inspector
    /// column on the Mac and in regular widths, a sheet in compact ones (the inspector's own
    /// behavior). Nothing when the feature isn't connected.
    func pullRequestAskPanel(for reference: PullRequestReference) -> some View {
        modifier(PullRequestAskPanelPresenter(reference: reference))
    }
}

private struct PullRequestAskPanelPresenter: ViewModifier {
    let reference: PullRequestReference

    @Environment(PullRequestAskCenter.self) private var center: PullRequestAskCenter?
    @Environment(\.inspectorRoom) private var inspectorRoom
    /// Follows the center, once the window has made room for the column.
    @State private var isPresented = false

    func body(content: Content) -> some View {
        if let center, center.isConnected {
            let wantsOpen = center.isPanelOpen(for: reference)
            content
                .inspector(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { shows in
                            isPresented = shows
                            // Closed from the inspector itself (a sheet swiped down, say).
                            if !shows { center.setPanelOpen(false, for: reference) }
                        })
                ) {
                    PullRequestAskPanel(conversation: center.conversation(for: reference))
                        .frame(minWidth: PullRequestAskMetrics.panelMinWidth)
                        // Native's band under the toolbar, as on the page beside it.
                        .dsToolbarBand()
                        .inspectorColumnWidth(
                            min: PullRequestAskMetrics.panelMinWidth, ideal: PullRequestAskMetrics.panelIdealWidth,
                            max: PullRequestAskMetrics.panelMaxWidth)
                }
                .onChange(of: wantsOpen, initial: true) { _, open in
                    guard open != isPresented else { return }
                    if open {
                        inspectorRoom.open(PullRequestAskMetrics.panelIdealWidth) { isPresented = true }
                    } else {
                        isPresented = false
                    }
                }
                .onChange(of: isPresented) { _, shows in
                    if !shows { inspectorRoom.release() }
                }
                // Another page took the pane; the panel went with it.
                .onDisappear { inspectorRoom.release() }
        } else {
            content
        }
    }
}
