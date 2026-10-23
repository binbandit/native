#if DEBUG
import ACP
import SwiftUI

@MainActor
enum TaskPeekPreviewFixtures {
    enum State: String, CaseIterable {
        case routine, destructive, question, failure, plan, finished, resolved, long

        var taskID: String {
            switch self {
            case .routine, .resolved, .long: "native-1"
            case .destructive: "native-4"
            case .question: "kite-1"
            case .failure: "pier-1"
            case .plan: "plan"
            case .finished: "native-2"
            }
        }
    }

    static func prepare(_ app: AppModel, state: State) -> TaskPeekPresentation.Request {
        let key = SessionKey(agent: AgentDefinition.ID(rawValue: "codex"), id: SessionID(state.taskID))
        if let session = app.session(key), state == .long {
            for call in session.permissionRequests { session.state.resolvePermission(toolCallID: call.id) }
            session.previewPermissionRequest(
                command:
                    "swift test --filter PermissionRequestTests.testPermissionResponsePreservesTheOriginalRequestWhenAnotherTaskAsksForApproval",
                at: .now.addingTimeInterval(-720))
        }
        let request = TaskPeekPresentation.Request(task: key, ask: app.taskAsks(for: key).first)
        if let session = app.session(key), state == .resolved {
            for call in session.permissionRequests { session.state.resolvePermission(toolCallID: call.id) }
        }
        return request
    }

    static func view(_ state: State, width: CGFloat = DS.Peek.width) -> some View {
        let app = SidebarDesignFixture.makeApp("plan")
        let request = prepare(app, state: state)
        return DSPreviewPair { TaskPeekView(request: request).frame(width: width) }.environment(app)
    }
}
#endif
