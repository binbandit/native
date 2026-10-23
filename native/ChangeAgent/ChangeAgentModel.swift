import ACP
import Foundation
import Observation

/// Holds an unsent replacement while the user reviews its handoff and live model choices.
@Observable
final class ChangeAgentModel {
    let source: SessionModel
    var agentID: AgentDefinition.ID?
    var handoff = ""
    var modelValue = ""
    private(set) var candidate: SessionModel?
    private(set) var isWorking = false
    private(set) var error: String?
    private(set) var isLoadingContext = true
    private var reviewedItems: [TranscriptItem] = []
    private var wasCancelled = false
    private weak var app: AppModel?

    init(source: SessionModel, app: AppModel) {
        self.source = source
        self.app = app
        agentID = app.changeAgentChoices(for: source).first?.agent.id
    }

    var choices: [AgentRuntime] { app?.changeAgentChoices(for: source) ?? [] }

    var modelOption: ConfigOption? { candidate?.configOptions.first { $0.category == "model" } }

    var modelChoices: [ConfigOption.SelectOption] {
        guard case .select(_, let choices) = modelOption?.kind else { return [] }
        return choices
    }

    var blockedReason: String? { app?.changeAgentBlock(for: source) }

    func loadContext() async {
        guard isLoadingContext, let app else { return }
        reviewedItems = source.state.items
        handoff = await app.changeAgentHandoff(source)
        isLoadingContext = false
    }

    func prepare() async {
        guard let app, let agentID, !isWorking, candidate == nil else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let prepared = try await app.prepareAgentChange(source, to: agentID)
            guard !wasCancelled else {
                app.discardAgentChange(prepared)
                return
            }
            candidate = prepared
            if case .select(let value, _) = modelOption?.kind { modelValue = value }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func send() async {
        guard let app, let candidate, !isWorking else { return }
        guard source.state.items == reviewedItems else {
            error = "The task changed while this handoff was open. Cancel and open Change Agent again to refresh it."
            return
        }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await app.finishAgentChange(
                source, to: candidate, handoff: handoff, modelValue: modelValue)
            self.candidate = nil
            app.changingAgent = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    #if DEBUG
    static func preview(in app: AppModel, source: SessionModel, error: String? = nil) -> ChangeAgentModel {
        let change = ChangeAgentModel(source: source, app: app)
        change.handoff = TaskHandoff.draft(
            title: source.displayTitle, state: source.state, changedPaths: ["Sources/Export.swift"],
            openQuestion: "Should exports include column headings?")
        change.isLoadingContext = false
        change.reviewedItems = source.state.items
        change.error = error
        return change
    }
    #endif

    func cancel() {
        // Starting an empty conversation can finish after dismissal; prepare() closes it then.
        // Once sending begins, wait for its result so cancellation cannot hide accepted work.
        guard !isWorking || candidate == nil else { return }
        wasCancelled = true
        if let candidate { app?.discardAgentChange(candidate) }
        candidate = nil
        app?.changingAgent = nil
    }
}
