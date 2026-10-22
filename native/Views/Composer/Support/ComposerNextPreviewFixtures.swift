#if DEBUG
import ACP
import Experiments
import NativeAutomation
import SwiftUI

/// Inert state for the quiet composer. Nothing starts an agent or saves a setting.
enum ComposerNextPreviewFixtures {
    @ViewBuilder
    static func composer(
        enabled: Bool = true, draft: String = "", phase: SessionModel.Phase = .idle,
        configure: (SessionModel) -> Void = { _ in }
    ) -> some View {
        let app = AppModel.preview(.empty)
        let session = session(in: app, draft: draft, phase: phase)
        let defaults = PreviewUserDefaults()
        let modes = TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults)
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        let _ = experiments.set(enabled, for: .composerNext)
        let automation = AutomationCenter(
            goalStore: GoalStore(url: URL(filePath: "/native-preview-unused/goals.json")),
            workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
        if let session {
            let _ = configure(session)
            ComposerView(session: session, taskModes: modes)
                .environment(app)
                .environment(automation)
                .environment(CommandRegistry.shared)
                .environment(\.experimentStore, experiments)
        }
    }

    static func queuedEdit(started: Bool) -> some View {
        composer(phase: .prompting) { session in
            session.queue.append("Check the empty queue")
            session.editingQueuedPrompt = session.queuedPrompts.first?.id
            session.draft = "Check the empty queue and keep these unsaved edits"
            if started { _ = session.queue.next() }
        }
    }

    private static func session(in app: AppModel, draft: String, phase: SessionModel.Phase) -> SessionModel? {
        let session = SessionModel.preview(in: app, phase: phase, configOptions: ComposerPreviewFixtures.configOptions)
        session?.draft = draft
        if !draft.isEmpty { session?.attachments = Array(ComposerPreviewFixtures.attachments.prefix(1)) }
        return session
    }

    @ViewBuilder
    static func surface(
        draft: String = "", agent: String = "Claude Code",
        settings: ComposerSettings = ComposerPreviewFixtures.settings
    ) -> some View {
        let app = AppModel.preview(.empty)
        let defaults = PreviewUserDefaults()
        let options = [settings.model, settings.effort, settings.autonomy].compactMap { $0?.option }
        let mode = SessionModel.preview(in: app, configOptions: options).map {
            TaskModeControl(
                session: $0, modes: TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults))
        }
        ComposerSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom) {
                    Text(draft.isEmpty ? "Message \(agent), or type / for commands" : draft)
                        .font(.dsCallout)
                        .foregroundStyle(draft.isEmpty ? .dsTextTertiary : .dsTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !draft.isEmpty { ComposerSendButton {} }
                }
                .padding(DS.Space.lg)
                .frame(minHeight: DS.Size.composerInputMinHeight)
                ComposerNextControlsRow(
                    settings: settings, agentName: agent, resumedAutonomy: "auto",
                    isModelPickerOpen: .constant(false), isPickingFiles: .constant(false), onAttach: { _ in },
                    onSet: { _, _ in }, onChooseAgent: {}, mode: mode,
                    extras: { EmptyView() }, context: { ContextUsageRing(fraction: 0.42) }
                )
            }
        }
    }
}

#Preview("Composer - Queued edit before and after starting") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ComposerNextPreviewFixtures.queuedEdit(started: false)
            ComposerNextPreviewFixtures.queuedEdit(started: true)
        }
        .frame(width: 860)
    }
}
#endif
