import ACP
import NativeCommands
import SwiftUI

extension CommandID {
    static let goBack: Self = "go.back"
    static let goForward: Self = "go.forward"
    static let goPullRequests: Self = "go.pullRequests"
    static let viewToggleSidebar: Self = "view.toggleSidebar"
    static let viewToggleSubagentInspector: Self = "view.toggleSubagentInspector"
    static let viewMCPServers: Self = "view.mcpServers"
    static let viewNeedsYouFilter: Self = "view.needsYouFilter"
    static let transcriptFoldEarlierTurns: Self = "transcript.foldEarlierTurns"
    static let transcriptJumpToLatest: Self = "transcript.jumpToLatest"
}

extension NativeCommand {
    /// History, and the pages that take the detail column.
    static func navigation(model: AppModel, settings: SettingsPresentation) -> [NativeCommand] {
        [
            // In Settings, Back returns to where you were, like its Back button and Escape.
            NativeCommand(.goBack, title: "Back", category: .navigation, systemImage: "chevron.backward") { _ in
                if settings.isShown {
                    settings.close()
                } else {
                    model.goBack()
                }
            }
            .available { _ in settings.isShown || model.canGoBack },

            NativeCommand(.goForward, title: "Forward", category: .navigation, systemImage: "chevron.forward") { _ in
                model.goForward()
            }
            .available { _ in !settings.isShown && model.canGoForward },

            NativeCommand(
                .goPullRequests, title: "Pull Requests", category: .navigation,
                systemImage: "arrow.triangle.pull", keywords: ["github", "pr"]
            ) {
                $0.pullRequestsPage?.wrappedValue = true
            }
            .available { $0.pullRequestsPage != nil },
        ]
    }

    /// The window's panels and filters.
    static let windowView: [NativeCommand] = [
        NativeCommand(.viewToggleSidebar, title: "Show or Hide Sidebar", category: .view, systemImage: "sidebar.left") {
            guard let visibility = $0.sidebarVisibility else { return }
            withAnimation {
                visibility.wrappedValue = visibility.wrappedValue == .detailOnly ? .all : .detailOnly
            }
        }
        .menuTitle { $0.sidebarVisibility?.wrappedValue == .detailOnly ? "Show Sidebar" : "Hide Sidebar" }
        .available { $0.sidebarVisibility != nil },

        NativeCommand(
            .viewToggleSubagentInspector, title: "Toggle Subagent Inspector", category: .view,
            systemImage: "sidebar.right"
        ) {
            $0.session?.isSubagentInspectorToggleRequested = true
        }
        .available { $0.session.map { !$0.state.subagents.isEmpty } ?? false },

        NativeCommand(
            .viewMCPServers, title: "Show MCP Servers", category: .view, systemImage: "server.rack",
            keywords: ["tools"]
        ) {
            $0.mcpServersPopover?.wrappedValue.toggle()
        }
        .available { $0.mcpServersPopover != nil },

        NativeCommand(
            .viewNeedsYouFilter, title: "Show Only Tasks That Need You", category: .view,
            systemImage: "line.3.horizontal.decrease", keywords: ["filter", "attention"]
        ) {
            $0.needsYouFilter?.wrappedValue.toggle()
        }
        .toggles { $0.needsYouFilter?.wrappedValue ?? false }
        .available { $0.needsYouFilter != nil },

        NativeCommand(
            .transcriptFoldEarlierTurns, title: "Fold Earlier Turns", category: .view,
            systemImage: "rectangle.compress.vertical", keywords: ["transcript", "collapse"]
        ) { _ in
            let defaults = UserDefaults.standard
            let folds = defaults.object(forKey: TranscriptPreferences.foldsEarlierTurnsKey) as? Bool ?? true
            defaults.set(!folds, forKey: TranscriptPreferences.foldsEarlierTurnsKey)
        },

        NativeCommand(
            .transcriptJumpToLatest, title: "Jump to Latest", category: .view, systemImage: "arrow.down.to.line",
            keywords: ["scroll", "bottom", "transcript"]
        ) {
            $0.jumpToLatest?.action()
        }
        .available { $0.jumpToLatest != nil },
    ]
}
