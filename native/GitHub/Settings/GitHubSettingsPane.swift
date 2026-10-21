import SwiftUI

extension SettingsPane.ID {
    static let gitHub = Self("gitHub")
}

extension SettingsPane {
    /// Settings › GitHub.
    static let gitHub = SettingsPane(
        id: .gitHub,
        title: "GitHub",
        systemImage: "arrow.triangle.pull",
        group: .agents,
        order: 26,
        keywords: ["pull request", "pr", "gh", "browser", "review"],
        searchEntries: {
            [
                SettingsSearchEntry(
                    id: GitHubSettingsPage.openingRow, title: "Open pull requests",
                    keywords: ["browser", "native", "pr"])
            ]
        },
        content: { GitHubSettingsPage() }
    )
}

/// GitHub settings: where pull requests open.
struct GitHubSettingsPage: View {
    static let openingRow = SettingsRowID("github.opening")

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        @Bindable var gitHub = gitHub
        @Bindable var accounts = gitHub.accounts
        SettingsPage {
            SettingsHeader(
                "GitHub",
                description: Text(
                    "Pull requests through your own GitHub CLI (gh): with an account choice just for Native."))
            #if os(macOS)
            SettingsRowGroup {
                SettingsRow(
                    "Account",
                    description: Text(
                        "Choose from accounts signed in with gh. Your terminal keeps its own active account.")
                ) {
                    Button("Manage Accounts…") { gitHub.accounts.showMenu() }
                        .buttonStyle(.settings)
                        .dsPopover(isPresented: $accounts.isMenuPresented) { GitHubAccountMenu() }
                }
            }
            #endif
            SettingsRowGroup {
                SettingsRow(
                    id: Self.openingRow, "Open pull requests",
                    description: Text(
                        "Clicking a pull request in the list, on a task or in a link opens its page in Native, where you can read and review it, or on GitHub in your browser."
                    )
                ) {
                    SettingsSelect(
                        label: "Open pull requests", selection: $gitHub.pullRequestOpening,
                        options: GitHubPullRequestOpening.allCases.map { .init(value: $0, title: $0.title) })
                }
            }
        }
    }
}

#if DEBUG
#Preview("GitHub settings") {
    DSPreviewPair {
        GitHubSettingsPage()
            .settingsPreviewPage()
    }
    .environment(GitHubModel.preview())
}
#endif
