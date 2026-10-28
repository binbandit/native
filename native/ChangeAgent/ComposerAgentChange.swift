import ACP
import Foundation
import NativePolicy
import Observation

/// One reversible, non-executing choice. A running source reaches idle before context is captured.
/// Until commit only the source is published; the unused candidate belongs to this attempt.
@Observable
final class ComposerAgentChange {
    enum Stage: Equatable { case waiting, preparing, applied, reversed, failed, cancelled }
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    let choice: ComposerAgentModel
    private(set) var stage: Stage = .waiting
    private(set) var error: String?
    private(set) var permissionNotice: String?
    private var permissionValue: String?
    private(set) var showsLoader = false
    var isReceiptDismissed = false { didSet { persistReceipt() } }
    private let earlierName: String
    private let earlierModel: String
    private let earlierModelValue: String?
    private var earlierKey: SessionKey
    private(set) var undoIsClosed = false
    private weak var source: SessionModel?
    private weak var current: SessionModel?
    private var previous: SessionModel?
    private var priorChoice: ComposerAgentChange?
    private weak var app: AppModel?
    private var candidate: SessionModel?
    @ObservationIgnored private var work: Task<Void, Never>?

    init(source: SessionModel, choice: ComposerAgentModel, app: AppModel) {
        self.source = source
        priorChoice = source.modelChange
        earlierName = source.agentName
        earlierModel = ComposerSettings(source.configOptions).model?.shortModelName ?? source.agentName
        earlierModelValue = ComposerSettings(source.configOptions).model?.value
        earlierKey = source.key
        self.choice = choice
        self.app = app
    }

    var isPending: Bool { stage == .waiting || stage == .preparing }
    var undoSelection: ComposerAgentChange? { canUndo ? self : priorChoice?.undoSelection }
    var canUndo: Bool { stage == .applied && !undoIsClosed && current?.hasSubmittedPrompt == false }
    var hasPermissionChoice: Bool {
        current.map { !ComposerSettings($0.configOptions).autonomyLevels.isEmpty } ?? false
    }
    var sourceName: String { earlierName }
    var sourceModel: String { earlierModel }

    init(restoring record: AgentModelContinuations.Receipt, current: SessionModel, app: AppModel) {
        earlierName = record.sourceName
        earlierModel = record.sourceModel
        earlierModelValue = record.sourceModelValue
        earlierKey = record.source
        choice = .init(
            agent: record.agent, agentName: record.agentName,
            choice: .init(value: record.modelValue ?? "", name: record.modelName),
            kind: .model(record.modelValue))
        self.current = current
        self.app = app
        stage = .applied
        permissionNotice = record.permissionNotice
        isReceiptDismissed = record.isDismissed
        undoIsClosed = !app.sessions.services.modelContinuations.hasPending(current.key)
    }

    private func persistReceipt() {
        guard stage == .applied, let current, let app, case .model(let value) = choice.kind else { return }
        app.sessions.services.modelContinuations.keep(
            .init(
                source: earlierKey, sourceName: earlierName, sourceModel: earlierModel,
                sourceModelValue: earlierModelValue,
                agent: choice.agent, agentName: choice.agentName, modelValue: value,
                modelName: choice.choice.name, isDismissed: isReceiptDismissed, permissionNotice: permissionNotice,
                confirmedChoices: Dictionary(
                    uniqueKeysWithValues: current.configOptions.compactMap { option in
                        guard option.category == "model" || option.category == "mode",
                            case .select(let value, _) = option.kind
                        else { return nil }
                        return (option.id, value)
                    })), for: current.key)
    }

    var receipt: String {
        switch stage {
        case .waiting: "Next model: \(choice.choice.displayName) · \(choice.agentName)"
        case .preparing: "Starting \(choice.agentName)…"
        case .applied: "Using \(choice.agentName) · \(choice.choice.displayName)"
        case .reversed: "Using \(sourceName) · \(sourceModel)"
        case .failed: error ?? "Couldn't change the model. Choose another model."
        case .cancelled: "Model change cancelled."
        }
    }

    func start(undoManager: UndoManager?) {
        guard work == nil, let source, let app else { return }
        source.isChangingAgent = true
        work = Task { [weak self] in
            guard let self else { return }
            defer { source.isChangingAgent = false; work = nil; showsLoader = false }
            do {
                if source.phase == .prompting {
                    for await phase in Observations({ source.phase }) {
                        try Task.checkCancellation()
                        if phase != .prompting { break }
                    }
                    guard source.phase == .idle, source.lastStopReason == .endTurn else {
                        throw Failure(
                            "The turn didn't finish normally. Cancel this choice and try again when the task is ready.")
                    }
                }
                try Task.checkCancellation()
                if let reason = app.changeAgentBlock(for: source) { throw Failure(reason) }
                stage = .preparing
                let loader = Task { [weak self] in
                    try? await Task.sleep(for: DS.ComposerSettings.applyingDelay)
                    if !Task.isCancelled { self?.showsLoader = true }
                }
                defer { loader.cancel() }
                let revision = source.state.items
                let config = source.configOptions
                let prepared = try await app.prepareModelRuntime(choice, for: source)
                candidate = prepared
                try Task.checkCancellation()
                try await configure(prepared, from: source)
                let latestContext = await app.changeAgentHandoff(source)
                let context =
                    source.services.modelContinuations.context(for: source.key).map {
                        String($0.prefix(24_000)) + "\n\n" + latestContext
                    } ?? latestContext
                try Task.checkCancellation()
                guard revision == source.state.items, config == source.configOptions else {
                    throw Failure("The task changed while the model was starting. Try Again to use its latest context.")
                }
                if let reason = app.changeAgentBlock(for: source) { throw Failure(reason) }
                try validate(prepared, source: source, app: app)
                // Mode state is Native-owned. Its task-start hook copies the selection locally,
                // with `continuing` set; it does not send a prompt or run new-task defaults.
                await source.services.hooks.taskStarted(prepared, source, nil)
                try Task.checkCancellation()
                guard revision == source.state.items, config == source.configOptions else {
                    throw Failure("The task changed while the model was starting. Try Again to use its latest context.")
                }
                if let reason = app.changeAgentBlock(for: source) { throw Failure(reason) }
                try validate(prepared, source: source, app: app)
                priorChoice?.closeUndo()
                priorChoice = nil
                app.commitAgentModel(self, source: source, target: prepared, context: context)
                previous = source
                current = prepared
                source.modelChange = nil
                prepared.modelChange = self
                candidate = nil
                stage = .applied
                persistReceipt()
                undoManager?.registerUndo(withTarget: self) { change in
                    MainActor.assumeIsolated { change.undo() }
                }
                undoManager?.setActionName("Model Change")
            } catch is CancellationError {
                stage = .cancelled
            } catch {
                self.error = error.localizedDescription
                stage = .failed
            }
            if let candidate { app.discardAgentChange(candidate); self.candidate = nil }
        }
    }

    private func configure(_ target: SessionModel, from source: SessionModel) async throws {
        switch choice.kind {
        case .load: throw Failure("Load the agent's models before choosing one.")
        case .model(let value):
            if let value {
                guard let model = ComposerSettings(target.configOptions).model,
                    model.choices.contains(where: { $0.value == value })
                else { throw Failure("\(choice.choice.displayName) is no longer available. Choose another model.") }
                await target.setConfigOption(model.option, to: value)
                guard ComposerSettings(target.configOptions).model?.value == value else {
                    throw Failure(
                        "Couldn't select \(choice.choice.displayName). \(source.agentName) is still selected.")
                }
            }
        }
        let sourceMode = ComposerSettings(source.configOptions).autonomy
        guard let targetMode = ComposerSettings(target.configOptions).autonomy, !targetMode.choices.isEmpty else {
            permissionValue = nil
            permissionNotice =
                "\(choice.agentName) doesn't offer a permission choice. Check its permissions before sending."
            return
        }
        let offered = permissionLevels(targetMode)
        guard
            let selection = AgentModelPermissions.selection(
                for: sourceMode?.value, offered: offered,
                forbidden: source.services.plugins.policyCenter.policy.forbiddenPermissionModes)
        else { throw permissionPolicyFailure(source.services.plugins.policyCenter.policy) }
        permissionValue = selection.value
        permissionNotice = permissionExplanation(selection, source: sourceMode, target: targetMode)
        await target.setConfigOption(targetMode.option, to: selection.value)
        guard ComposerSettings(target.configOptions).autonomy?.value == selection.value else {
            throw Failure(
                "Couldn't set \(choice.agentName)'s permissions. \(source.agentName) is still selected. Try Again.")
        }
    }

    private func permissionLevels(_ setting: SelectSetting) -> [String] {
        let levels = setting.choices.map(\.value).filter { $0 != ComposerSettings.planValue }
        return levels.isEmpty ? setting.choices.map(\.value) : levels
    }

    private func permissionPolicyFailure(_ policy: NativePolicy) -> Failure {
        let manager = policy.organizationName ?? "Your organization"
        return Failure(
            "\(manager) doesn't allow any of \(choice.agentName)'s permission levels. Keep the current agent or contact your administrator."
        )
    }

    private func permissionExplanation(
        _ selection: AgentModelPermissions.Selection, source: SelectSetting?, target: SelectSetting
    ) -> String? {
        let level = target.choices.first { $0.value == selection.value }
        let name = level?.askingTitle.lowercased() ?? selection.value
        switch selection.reason {
        case .equivalent:
            return nil
        case .stricter:
            let earlier = source?.current?.askingTitle.lowercased() ?? source?.value ?? "the previous level"
            let consequence = selection.value == "dontAsk" ? "refuse anything not already allowed" : "ask \(name)"
            return "\(choice.agentName) doesn't offer '\(earlier)', so it will \(consequence)."
        case .safestAvailable:
            return
                "\(choice.agentName) has no level that asks as often. Its safest level is '\(name)'. Review permissions before sending."
        case .unknown:
            return
                "These permission levels can't be compared. \(choice.agentName) will use '\(name)'. Review permissions before sending."
        }
    }

    private func validate(_ target: SessionModel, source: SessionModel, app: AppModel) throws {
        guard app.plugins.policyCenter.policy.agents.allows(choice.agent.rawValue),
            target.agent.id == choice.agent, target.cwd == source.cwd,
            app.agentChangePlace(of: target) == app.agentChangePlace(of: source),
            app.sessions.session(target.key) === target, !target.hasStarted,
            target.phase == .idle, !target.isRestoringHistory, target.sendBlockedReason == nil
        else { throw Failure("The chosen agent is no longer ready on this task's host. Try Again.") }
        if case .model(let value) = choice.kind, let value,
            ComposerSettings(target.configOptions).model?.value != value
        {
            throw Failure("\(choice.choice.displayName) is no longer available. Choose another model.")
        }
        let actual = ComposerSettings(target.configOptions).autonomy
        if let actual, !actual.choices.isEmpty {
            let allowed = permissionLevels(actual).filter {
                !app.plugins.policyCenter.policy.forbiddenPermissionModes.contains($0)
            }
            guard !allowed.isEmpty else { throw permissionPolicyFailure(app.plugins.policyCenter.policy) }
            let expected = AgentModelPermissions.selection(
                for: ComposerSettings(source.configOptions).autonomy?.value,
                offered: permissionLevels(actual),
                forbidden: app.plugins.policyCenter.policy.forbiddenPermissionModes)
            guard actual.value == permissionValue, expected?.value == permissionValue else {
                throw Failure("The task's permissions changed. Choose a model again.")
            }
        } else if permissionValue != nil {
            throw Failure("The task's permissions changed. Choose a model again.")
        }
    }

    func replaceReference(_ old: SessionKey, with replacement: SessionKey) {
        if earlierKey == old { earlierKey = replacement }
        priorChoice?.replaceReference(old, with: replacement)
    }

    func replace(_ old: SessionModel, with replacement: SessionModel) {
        replaceReference(old.key, with: replacement.key)
        if source === old { source = replacement }
        if previous === old { previous = replacement }
        if current === old { current = replacement }
        if candidate === old { candidate = replacement }
    }

    func cancel() {
        guard isPending else { return }
        work?.cancel()
        source?.isChangingAgent = false
        stage = .cancelled
    }

    func closeUndo() {
        undoIsClosed = true
        previous?.isModelChangeSource = false
        previous = nil
    }

    func retry(undoManager: UndoManager?) {
        guard stage == .failed, let source, let app else { return }
        app.chooseAgentModel(choice, for: source, undoManager: undoManager)
    }

    func undo() {
        guard canUndo, let current, let app else { return }
        guard let previous = previous ?? app.sessions.session(earlierKey) else {
            Task {
                await app.loadSession(earlierKey)
                if let restored = app.sessions.session(earlierKey) {
                    self.previous = restored
                    undo()
                } else {
                    error = "Couldn't reopen \(earlierName). Try again when its host is available."
                }
            }
            return
        }
        guard
            current.phase == .idle, !current.hasQueuedPrompts,
            app.plugins.policyCenter.policy.agents.allows(previous.agent.id.rawValue)
        else { return }
        app.undoAgentModel(self, source: previous, target: current)
        source = previous
        self.previous = nil
        self.current = nil
        stage = .reversed
        isReceiptDismissed = false
        previous.modelChange = self
        current.modelChange = nil
    }

    func continueWithSource() {
        guard !canUndo, stage == .applied, let current, let app else { return }
        let choice = ComposerAgentModel(
            agent: earlierKey.agent, agentName: earlierName,
            choice: .init(value: earlierModelValue ?? "", name: earlierModel), kind: .model(earlierModelValue))
        app.chooseAgentModel(choice, for: current)
    }
}
