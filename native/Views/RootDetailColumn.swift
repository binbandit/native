import SwiftUI

/// Notices and the page share a width floor, including when AppKit measures the window's minimum.
struct RootDetailColumn<Notices: View, Content: View>: View {
    @ViewBuilder var notices: Notices
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            notices
            content
        }
        // A full-height notice measured at zero width becomes a character per line and grows the
        // window past the screen. The page's own width floor cannot protect its siblings.
        .platformMinimumContentWidth(DS.Window.detailMinWidth)
    }
}

#if DEBUG
import NativeHostClient
import NativeHostProtocol

#Preview("Root detail - Recovery notice at narrow width") {
    let session = HostSessionID()
    let summary = AwaySummary(
        entries: [
            ActivityEntry(
                id: 1, at: .now, sessionID: session, kind: .recovered,
                subject: "Window growth fixture",
                recovery: RecoveryNote(
                    cause: .hostStopped, action: .resumed, agentName: "Preview Agent", interruptedAt: .now)),
            ActivityEntry(id: 2, at: .now, sessionID: session, kind: .turnFinished),
        ], sessions: [])
    DSPreviewPair {
        RootDetailColumn {
            if let summary {
                HostAwayCard(summary: summary, title: { _ in nil }, open: { _ in nil }, onDismiss: {})
                    .padding(DS.Space.md)
            }
        } content: {
            Spacer(minLength: 0)
        }
        .frame(width: 400, height: 360)
    }
}

#Preview("Root detail - No notices") {
    DSPreviewPair {
        RootDetailColumn {
            EmptyView()
        } content: {
            Text("No background activity")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 400, height: 360)
    }
}
#endif
