#if DEBUG
import ACP
import Foundation
import NativeAutomation
import NativeHostProtocol
import SwiftUI

enum ComposeTaskPreviewFixtures {
    static let prompt =
        "The device pill should say how long a droid has been offline, like ‘Offline · 12 min’. Put it in @native/Hosts/Components/HostDevicePill.swift and the picker row, and add a preview of the offline state in light and dark."

    static func model(_ state: String) -> AppModel {
        let model = AppModel.preview(state == "firstLaunch" ? .empty : .populated)
        model.quickEntry.project = model.previewProject()?.id
        model.quickEntry.agent = model.agents.first(where: { $0.agent.id.rawValue == "codex" })?.agent.id
        model.prepareComposeEditor()
        configure(model, state: state)
        return model
    }

    static func applyLaunchState(to model: AppModel) {
        guard let state = UserDefaults.standard.string(forKey: "composeTaskFixture") else { return }
        configure(model, state: state)
    }

    static func configure(_ model: AppModel, state: String) {
        let compose = model.composeTask
        let entry = model.quickEntry
        entry.agent = AgentDefinition.ID(rawValue: state == "firstLaunch" ? "claude-code" : "codex")
        model.prepareComposeEditor()
        compose.previewState = state
        compose.isPresented = true
        compose.previewBranch = "main"
        compose.workspace = .newWorktree
        compose.editor?.draft = state == "firstLaunch" || state == "empty" ? "" : prompt
        compose.options = state == "firstLaunch" ? claudeOptions : options
        compose.defaults = ComposeTaskModel.addressedChoices(in: compose.options)
        if state == "attachments" {
            compose.editor?.attachments = [
                PromptAttachment(
                    url: URL(filePath: "Host device.png"),
                    content: .image(ComposerPreviewFixtures.screenshot, mimeType: "image/png"), byteCount: 124000)
            ]
        }
        if state == "consequences", let setting = ComposerSettings(compose.options).effort {
            compose.choose(setting, value: "high")
        }
        if state == "firstLaunch" {
            entry.project = nil
            compose.workspace = nil
            compose.previewBranch = nil
        }
        if state == "failure" {
            entry.failure = "The folder is unavailable. Restore it or choose another folder. Your draft is kept."
        }
        if state == "project" { entry.picker = .project }
        if state == "agents" { entry.picker = .agent }
        if state == "twoAgents" {
            compose.workspaces = [
                TaskWorkspaceOption(choice: .newWorktree, title: "Its own worktree", detail: "", isCurrent: false)
            ]
            compose.second = ComposeRecipient(
                agent: AgentDefinition.ID(rawValue: "claude-code"), options: claudeOptions)
        }
        if state == "devices" || state == "offline" || state == "held" {
            compose.previewOfflineSince = Calendar.current.date(bySettingHour: 14, minute: 14, second: 0, of: .now)
            let remote = SessionDevice.remote(RemoteHostID())
            entry.previewDeviceOptions = [
                .init(
                    device: .thisMac, name: "This Mac", availability: .online,
                    checkout: .present(path: "~/Developer/native")),
                .init(
                    device: remote, name: "elara",
                    availability: .offline(
                        reason: "Nothing has answered at elara.tail4c2e.ts.net for 6 minutes."),
                    checkout: .present(path: "~/code/native")),
            ]
            if state != "devices" { entry.device = remote } else { entry.picker = .device }
            compose.isHeld = state == "held"
        }
        if ["folding", "message", "settled"].contains(state) {
            compose.stage = state == "folding" ? .folding : state == "message" ? .message : .settled
        }
    }

    static var options: [ConfigOption] {
        let json = """
            [
            {"id":"model","name":"Model","category":"model","type":"select","currentValue":"gpt-6.1-sol","options":[{"value":"gpt-6.1-sol","name":"6.1 Sol"},{"value":"gpt-6-astra","name":"6 Astra"}]},
            {"id":"effort","name":"Effort","category":"thought_level","type":"select","currentValue":"low","options":[{"value":"low","name":"Low","description":"Quick, and light on usage"},{"value":"high","name":"High","description":"Slower, more thorough"}]},
            {"id":"mode","name":"Permissions","category":"mode","type":"select","currentValue":"workspace-write","options":[{"value":"read-only","name":"Before any change"},{"value":"workspace-write","name":"Before leaving the worktree"},{"value":"agent-full-access","name":"Never"}]}
            ]
            """
        return (try? JSONDecoder().decode([ConfigOption].self, from: Data(json.utf8))) ?? []
    }

    static var claudeOptions: [ConfigOption] {
        let json = """
            [{"id":"model","name":"Model","category":"model","type":"select","currentValue":"sonnet","options":[{"value":"opus","name":"Opus 5.5"},{"value":"sonnet","name":"Sonnet 5.5"}]}]
            """
        return (try? JSONDecoder().decode([ConfigOption].self, from: Data(json.utf8))) ?? []
    }

    static func automation() -> AutomationCenter {
        AutomationCenter(
            goalStore: GoalStore(
                url: FileManager.default.temporaryDirectory.appending(path: "compose-preview-unused.json")),
            workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
    }
}

struct ComposeTaskPreviewFixture: View {
    let state: String
    var body: some View {
        DSPreviewPair {
            let model = ComposeTaskPreviewFixtures.model(state)
            ComposeTaskPage(model: model, compose: model.composeTask, entry: model.quickEntry)
                .environment(model).environment(ComposeTaskPreviewFixtures.automation())
                .frame(width: state == "narrow" ? 480 : 1000, height: 720)
        }
    }
}
#endif
