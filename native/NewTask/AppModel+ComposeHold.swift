import ACP
import Foundation
import NativePolicy

extension AppModel {
    func holdComposeTask() {
        #if DEBUG
        if composeTask.previewState != nil {
            composeTask.isHeld = true
            quickEntry.picker = nil
            return
        }
        #endif
        guard composeTask.stage == .writing, composeTask.hasContent, !composeTask.pendingAttachments,
            !composeTask.isHeld, let project = quickEntry.project, let agent = quickEntry.agent,
            let editor = composeTask.editor, quickEntry.device.isRemote,
            let option = composeDeviceOption, !option.canStart,
            PolicyCenter.shared.policy.agents.allows(agent.rawValue)
        else { return }
        if case .cannotClone = option.checkout { return }
        do {
            try composeTask.hold(
                ComposeHeldDraft(
                    project: project, agent: agent, device: quickEntry.device, text: editor.draft,
                    files: editor.attachments.map(ComposeHeldDraft.File.init), choices: composeTask.addressedChoices,
                    workspace: composeTask.workspace, second: composeTask.second?.agent,
                    secondChoices: composeTask.second?.choices))
            quickEntry.failure = nil
        } catch {
            quickEntry.failure = "Couldn't hold the task. Your draft is kept. Try again."
        }
    }

    func restoreComposeHold() {
        guard let held = composeTask.heldDraft else { return }
        quickEntry.project = held.project
        quickEntry.agent = held.agent
        quickEntry.device = held.device
        quickEntry.draft = held.text
        quickEntry.context = nil
        composeTask.editor = nil
        prepareComposeEditor()
        composeTask.editor?.attachments = held.files.map(\.attachment)
        composeTask.choices = held.choices.filter { composeTask.defaults[$0.key] != $0.value }
        for (index, option) in composeTask.options.enumerated() {
            guard let category = option.category, let value = held.choices[category],
                case .select(_, let choices) = option.kind, choices.contains(where: { $0.value == value })
            else { continue }
            composeTask.options[index].kind = .select(currentValue: value, options: choices)
        }
        composeTask.workspace = held.workspace
        if let second = held.second {
            var options = composeStartingOptions(for: second, in: projects.project(held.project))
            for (index, option) in options.enumerated() {
                guard let category = option.category, let value = held.secondChoices?[category],
                    case .select(_, let choices) = option.kind, choices.contains(where: { $0.value == value })
                else { continue }
                options[index].kind = .select(currentValue: value, options: choices)
            }
            composeTask.second = ComposeRecipient(agent: second, options: options)
        }
    }

    func resumeComposeHold(on host: RemoteHost) {
        guard quickEntry.isEnabled, let held = composeTask.heldDraft, held.device == .remote(host.id), host.isOnline
        else { return }
        restoreComposeHold()
        let wasPresented = composeTask.isPresented
        composeTask.isHeld = false
        startComposeTask(revealing: wasPresented)
        if composeTask.starting != nil {
            composeTask.cancelHold()
        } else {
            // A policy change or a missing file requires the user, never an automatic fallback.
            composeTask.isHeld = true
        }
    }
}
