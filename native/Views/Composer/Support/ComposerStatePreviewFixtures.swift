#if DEBUG
import ACP
import Experiments
import NativeAutomation
import SwiftUI

/// The ordinary composer, with inert sessions and task-mode defaults kept in memory.
enum ComposerStatePreviewFixtures {
    @ViewBuilder static func finePrint(phase: SessionModel.Phase, draft: String = "") -> some View {
        let app = AppModel.preview(.empty)
        let defaults = PreviewUserDefaults()
        let modes = TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults)
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        let _ = experiments.set(true, for: .composerNext)
        let automation = AutomationCenter(
            goalStore: GoalStore(url: URL(filePath: "/native-preview-unused/goals.json")),
            workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
        if let session = SessionModel.preview(
            in: app, phase: phase, configOptions: ComposerPreviewFixtures.configOptions)
        {
            let _ = { session.draft = draft }()
            ComposerView(session: session, taskModes: modes)
                .environment(app).environment(automation).environment(CommandRegistry.shared)
                .environment(\.experimentStore, experiments)
        }
    }

    @ViewBuilder static func queuedEdit(started: Bool) -> some View {
        let app = AppModel.preview(.empty)
        let defaults = PreviewUserDefaults()
        let modes = TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults)
        let automation = AutomationCenter(
            goalStore: GoalStore(url: URL(filePath: "/native-preview-unused/goals.json")),
            workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
        if let session = SessionModel.preview(
            in: app, phase: .prompting,
            configOptions: ComposerPreviewFixtures.configOptions)
        {
            let _ = configure(session, started: started)
            ComposerView(session: session, taskModes: modes)
                .environment(app).environment(automation).environment(CommandRegistry.shared)
        }
    }

    private static func configure(_ session: SessionModel, started: Bool) {
        session.queue.append("Check the empty queue")
        session.editingQueuedPrompt = session.queuedPrompts.first?.id
        session.draft = "Check the empty queue and keep these unsaved edits"
        if started { _ = session.queue.next() }
    }
}

#Preview("Composer - queued edit before and after start") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerStatePreviewFixtures.queuedEdit(started: false)
            ComposerStatePreviewFixtures.queuedEdit(started: true)
        }.frame(width: 760)
    }
}

#Preview("Composer - Fine print rest, typing, loading and unavailable") {
    DSPreviewPair {
        VStack {
            ComposerStatePreviewFixtures.finePrint(phase: .idle)
            ComposerStatePreviewFixtures.finePrint(phase: .idle, draft: "Keep the queued message in its place.")
            ComposerStatePreviewFixtures.finePrint(phase: .loading)
            ComposerStatePreviewFixtures.finePrint(phase: .disconnected)
        }.frame(width: DS.ComposerSettings.width)
    }
}

#Preview("Composer - Fine print narrow") {
    DSPreviewPair {
        ComposerStatePreviewFixtures.finePrint(phase: .idle)
            .frame(width: DS.ComposerSettings.popoverWidth)
    }
}
#endif
