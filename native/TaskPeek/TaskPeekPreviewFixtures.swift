#if DEBUG
import ACP
import Experiments
import SwiftUI

@MainActor
enum TaskPeekPreviewFixtures {
    enum State: String, CaseIterable {
        case routine, destructive, question, failure, recovering, plan, finished, resolved, long, loading, missing
        case answerFailure

        var taskID: String {
            switch self {
            case .routine, .resolved, .long, .answerFailure: "native-1"
            case .destructive: "native-4"
            case .question: "kite-1"
            case .failure, .recovering: "pier-1"
            case .plan: "plan"
            case .finished: "native-2"
            case .loading: "native-0"
            case .missing: "missing"
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
        if state == .loading { app.session(key)?.phase = .loading }
        if state == .recovering { app.taskPeek.isRecovering = true }
        if state == .answerFailure { app.taskPeek.answerFailure = "The connection closed before the answer was sent." }
        let request = TaskPeekPresentation.Request(task: key, ask: app.taskAsks(for: key).first)
        if let session = app.session(key), state == .resolved {
            for call in session.permissionRequests { session.state.resolvePermission(toolCallID: call.id) }
        }
        return request
    }

    /// `finePrint` turns on the composer's annotated asks (`NativeComposerNext`).
    static func view(_ state: State, width: CGFloat = DS.Peek.width, finePrint: Bool = false) -> some View {
        let app = SidebarDesignFixture.makeApp("plan")
        let request = prepare(app, state: state)
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(finePrint, for: .composerNext)
        return DSPreviewPair { TaskPeekView(request: request).frame(width: width) }
            .environment(app).environment(\.experimentStore, experiments)
    }
}
#endif
