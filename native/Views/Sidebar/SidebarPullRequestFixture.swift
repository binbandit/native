#if DEBUG
import SwiftUI

/// The real sidebar and Peek with inert outcomes. The harness separately exercises git/gh wiring.
struct SidebarPullRequestFixture: View {
    var showsPeek = false
    var showsAttention = false
    @State private var defaults = SidebarPullRequestPreviewFixtures.defaults()
    @State private var app = SidebarPullRequestPreviewFixtures.model()
    @State private var git = SidebarPullRequestPreviewFixtures.git()
    @State private var gitHub = SidebarPullRequestPreviewFixtures.gitHub()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView {
                EmptyView()
            } accessories: {
                EmptyView()
            } taskAccessory: { _ in
                EmptyView()
            }
            .frame(width: DS.Size.sidebarWidth)
            SeparatorLine(axis: .vertical)
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                Text("Fix failing tests").font(.dsTitle2)
                Text("The change is ready to review.").font(.dsBody).foregroundStyle(.dsTextSecondary)
                if showsAttention {
                    TaskAttentionList()
                        .frame(width: DS.Sidebar.attentionWidth)
                        .dsOverlayBackground(in: .rect(cornerRadius: DS.Radius.panel))
                }
                Spacer()
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.dsSurface)
        }
        .taskPeekHost()
        .defaultAppStorage(defaults)
        .environment(app)
        .environment(gitHub)
        .environment(\.sidebarTaskInsights, AppSidebarTaskInsights.make(model: app, git: git, gitHub: gitHub))
        .task {
            if showsAttention, let key = app.selection, let session = app.session(key) {
                session.previewRunningTurn("Run the tests")
                session.previewPermissionRequest(command: "swift test")
            }
            if showsPeek, let key = app.selection { app.taskPeek.request = .init(task: key, ask: nil) }
        }
    }
}

#Preview("Sidebar - Pull request outcomes, facts hidden") {
    let app = SidebarPullRequestPreviewFixtures.model()
    let git = SidebarPullRequestPreviewFixtures.git()
    let gitHub = SidebarPullRequestPreviewFixtures.gitHub()
    DSPreviewPair {
        AllInViewPreviewList(app: app, insights: AppSidebarTaskInsights.make(model: app, git: git, gitHub: gitHub))
    }
    .defaultAppStorage(SidebarPullRequestPreviewFixtures.defaults())
}
#Preview("Peek - Pull request with failing checks") {
    let app = SidebarPullRequestPreviewFixtures.model()
    let git = SidebarPullRequestPreviewFixtures.git()
    let gitHub = SidebarPullRequestPreviewFixtures.gitHub()
    DSPreviewPair {
        if let key = app.selection {
            TaskPeekView(request: .init(task: key, ask: nil)).frame(width: DS.Peek.width)
        }
    }
    .environment(app)
    .environment(\.sidebarTaskInsights, AppSidebarTaskInsights.make(model: app, git: git, gitHub: gitHub))
}
#endif
