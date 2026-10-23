import ACP
import SwiftUI

struct HomeNextPlanView: View {
    let session: SessionModel
    let call: ToolCallState
    let choose: (PermissionOption) -> Void
    @State private var isExpanded = false

    var body: some View {
        let entries = session.state.currentTurnPlan
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text(
                entries.isEmpty
                    ? "\(session.agentName) has a plan" : "\(session.agentName) has a plan: \(entries.count) steps"
            )
            .font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
            if !entries.isEmpty {
                ComposerPlanSection(
                    plan: PlanProgress(entries: entries), isWorking: false,
                    isExpanded: $isExpanded, presentation: .review)
            }
            // Progress updates are not bound to permission requests. The exact proposal must stay visible.
            ToolCallView(call: call, permissionPresentation: .planReview, onChoose: choose)
        }
    }
}

#if DEBUG
#Preview("Next plan - First five steps") { HomeNextPreviewFixtures.page(.plan) }
#Preview("Next plan - Permission without steps") { HomeNextPreviewFixtures.page(.planText) }
#Preview("Next plan - Previous turn's checklist") { HomeNextPreviewFixtures.page(.planRetained) }
#Preview("Next plan - Narrow") { HomeNextPreviewFixtures.page(.plan, narrow: true) }
#endif
