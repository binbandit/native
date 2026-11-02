#if DEBUG
import ACP
import Experiments
import NativeAutomation
import SwiftUI

enum ComposerPendingPreviewFixtures {
    enum State {
        case working, stopped, question, approval
    }

    @ViewBuilder
    static func composer(_ state: State) -> some View {
        let app = AppModel.preview(.empty)
        let defaults = PreviewUserDefaults()
        let modes = TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults)
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        let automation = AutomationCenter(
            goalStore: GoalStore(url: URL(filePath: "/native-preview-unused/goals.json")),
            workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
        if let session = SessionModel.preview(
            in: app, agent: "claude-code", title: "Check the composer", phase: state == .stopped ? .idle : .prompting,
            configOptions: ComposerPreviewFixtures.configOptions)
        {
            let _ = prepare(session, state: state)
            ComposerView(session: session, taskModes: modes)
                .environment(app).environment(automation).environment(CommandRegistry.shared)
                .environment(\.experimentStore, experiments)
                .frame(width: DS.ComposerField.previewWidth)
        }
    }

    private static func prepare(_ session: SessionModel, state: State) {
        session.previewRunningTurn("Check the layout and its focused tests.")
        session.composerMessage = "Keep this draft while I answer."
        switch state {
        case .working, .stopped:
            session.queue.append("Check the narrow layout too.")
            session.queue.append("Then run the focused tests.")
            if state == .stopped {
                session.phase = .idle
                session.lastStopReason = .cancelled
                session.queue.pause()
            }
        case .question:
            let json = """
                {"sessionId":"\(session.id.rawValue)","mode":"form","message":"Which layout should I check?",
                 "requestedSchema":{"type":"object","properties":{"layout":{"type":"string",
                 "title":"Layout","enum":["Narrow","Wide"]}}}}
                """
            if let request = SessionModel.previewDecode(CreateElicitationRequest.self, json) {
                session.requestQuestion(request, id: .int(1))
            }
        case .approval:
            session.previewPermissionRequest(
                command: "swift test --filter ComposerTests", reason: "Check the changed layout.")
        }
    }
}

#Preview("Composer pending - Working queue and stopped queue") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ComposerPendingPreviewFixtures.composer(.working)
            ComposerPendingPreviewFixtures.composer(.stopped)
        }
    }
}

#Preview("Composer pending - Question keeps the draft visible") {
    DSPreviewPair { ComposerPendingPreviewFixtures.composer(.question) }
}

#Preview("Composer pending - Approval keeps the draft visible") {
    DSPreviewPair { ComposerPendingPreviewFixtures.composer(.approval) }
}
#endif
