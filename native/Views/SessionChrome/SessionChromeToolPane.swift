#if DEBUG
import ProjectActions
import SwiftUI
import Terminal

/// One tool's pane, the same wherever the tool lives; existing views, hosted as they are.
struct SessionChromeToolPane: View {
    let tool: SessionChromeTool
    let context: SessionChromeContext
    let chrome: SessionChromeModel
    /// False where the place lists the terminal's tabs itself.
    var showsTerminalTabs = true

    var body: some View {
        switch tool {
        case .changes:
            GitChangesInspector(model: context.repository, review: context.changesReview, session: context.session) {
                Task { await GitHubGitWiring.createPullRequest(from: context.repository, gitHub: context.gitHub) }
            }
        case .terminal:
            SessionChromeTerminalPane(panel: context.terminal, store: context.terminals, showsTabBar: showsTerminalTabs)
        case .run:
            SessionChromeRunPane(context: context) { action in
                if let tab = context.terminal.tabs.tab(forJob: action.id.rawValue) {
                    context.terminal.select(tab.id)
                }
                chrome.show(.terminal)
            }
        case .agents:
            SessionChromeAgentsPane(session: context.session, chrome: chrome)
        case .pullRequest:
            SessionChromePullRequestPane(context: context)
        case .openIn:
            EmptyView()
        }
    }
}
#endif
