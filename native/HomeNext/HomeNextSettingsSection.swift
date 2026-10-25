import SwiftUI

/// What Home adds beyond its asks. Every addition is off until the user turns it on here.
struct HomeNextSettingsSection: View {
    static func row(_ summary: HomeNextSummary) -> SettingsRowID { SettingsRowID("general.home.\(summary.rawValue)") }

    static var searchEntries: [SettingsSearchEntry] {
        HomeNextSummary.allCases.map { summary in
            SettingsSearchEntry(
                id: row(summary), title: "Home: \(summary.title)", description: summary.detail,
                keywords: ["home", "summary", "up next"])
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(GitHubModel.self) private var gitHub: GitHubModel?

    var body: some View {
        SettingsGroup(
            title: "Home",
            footer: "With these off, Home shows what needs you, what's next and what's working. "
                + "While you were away is counted on this Mac and never leaves it."
        ) {
            ForEach(HomeNextSummary.allCases) { summary in
                HomeNextSummarySwitch(summary: summary, requirement: requirement(for: summary))
                    .settingsRevealTarget(Self.row(summary))
            }
        }
    }

    /// The feature a summary reads from, when it's missing; the switch still records the choice.
    private func requirement(for summary: HomeNextSummary) -> String? {
        switch summary {
        case .reviews:
            gitHub?.currentLogin == nil ? "Shows once Native is signed in to GitHub, under Accounts below." : nil
        case .usageLimits:
            model.plugins.isEnabled(BuiltInPlugins.usage.manifest.id)
                ? nil : "Shows once Usage is turned on in Extensions."
        case .away:
            nil
        }
    }
}

private struct HomeNextSummarySwitch: View {
    let summary: HomeNextSummary
    let requirement: String?
    @AppStorage private var isOn: Bool

    init(summary: HomeNextSummary, requirement: String?) {
        self.summary = summary
        self.requirement = requirement
        _isOn = AppStorage(wrappedValue: false, summary.storageKey)
    }

    var body: some View {
        SettingsRow(
            id: HomeNextSettingsSection.row(summary), summary.title, description: Text(summary.detail),
            detail: requirement.map { Text($0) }
        ) {
            SettingsSwitch(summary.title, isOn: $isOn)
        }
    }
}

#if DEBUG
#Preview("Home settings - Calm default") {
    DSPreviewPair {
        SettingsPage { HomeNextSettingsSection() }
            .settingsPreviewPage()
    }
    .environment(AppModel.preview())
    .environment(SettingsPresentation())
    .defaultAppStorage(PreviewUserDefaults())
}
#endif
