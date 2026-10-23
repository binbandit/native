import ACP
import SwiftUI

struct HomeNextPlanView: View {
    let session: SessionModel
    let call: ToolCallState
    let choose: (PermissionOption) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text(
                session.plan.isEmpty
                    ? "\(session.agentName) has a plan" : "\(session.agentName) has a plan: \(session.plan.count) steps"
            )
            .font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
            if !session.plan.isEmpty {
                ComposerPlanSection(
                    plan: PlanProgress(entries: session.plan), isWorking: false,
                    isExpanded: $isExpanded, presentation: .review)
            } else {
                // Some agents put the entire proposal in the permission payload, without plan updates.
                ToolCallView(call: call, onChoose: choose)
            }
            if !session.plan.isEmpty, let permission = call.permission {
                ToolPermissionButtons(options: permission.options, onChoose: choose, presentation: .planReview)
            }
        }
    }
}

#if DEBUG
#Preview("Next plan - First five steps") { HomeNextPreviewFixtures.page(.plan) }
#Preview("Next plan - Permission without steps") { HomeNextPreviewFixtures.page(.planText) }
#Preview("Next plan - Narrow") { HomeNextPreviewFixtures.page(.plan, narrow: true) }
#endif
