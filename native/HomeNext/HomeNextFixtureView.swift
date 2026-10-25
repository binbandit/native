#if DEBUG
import NativePolicy
import SwiftUI

struct HomeNextFixtureView: View {
    @State private var model: AppModel?
    let state: HomeNextPreviewFixtures.State
    /// Off, only the start field shows, for its own preview.
    var showsPage = true
    @State private var gitHub: GitHubModel?
    @State private var storage: UserDefaults?
    @State private var policy: PolicyCenter?

    private var managedValues: [String: Any] {
        guard state == .managed else { return [:] }
        return [
            PolicyKey.organizationName.rawValue: "Northwind Federal IT",
            PolicyKey.remoteHostsEnabled.rawValue: false,
            PolicyKey.forbiddenPermissionModes.rawValue: ["bypassPermissions", "dontAsk"],
        ]
    }

    var body: some View {
        Group {
            if let model, let policy, let storage {
                Group {
                    if showsPage {
                        HomeNextView(agents: HomeNextPreviewFixtures.agents, isLoading: state == .loading)
                            .taskPeekHost()
                    } else {
                        HomeNextStartField { _ in }
                    }
                }
                .environment(model)
                .environment(policy)
                .environment(gitHub)
                .defaultAppStorage(storage)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Creating a preview registry updates the experiment catalog. Do it once after layout,
            // never in init: a gate's redraw would otherwise create another registry indefinitely.
            guard model == nil else { return }
            policy = PolicyCenter(source: StaticPolicySource(managed: managedValues))
            model = HomeNextPreviewFixtures.model(state)
            gitHub = HomeNextPreviewFixtures.gitHub(state)
            storage = HomeNextPreviewFixtures.summaryDefaults(state)
        }
    }
}

#Preview("Next fixture - First launch") { HomeNextPreviewFixtures.page(.first) }
#endif
