#if DEBUG
import NativeHostProtocol
import SwiftUI

enum QuickEntryPreviewFixtures {
    enum State {
        case empty, selection, firstLaunch, failure, offline, narrow, devices, agents, projects
    }

    static func model(_ state: State) -> AppModel {
        let model = AppModel.preview(state == .firstLaunch ? .empty : .populated)
        let entry = model.quickEntry
        entry.isPresented = true
        entry.project = model.previewProject()?.id
        entry.agent = model.agents.first?.agent.id
        if state != .empty && state != .firstLaunch {
            entry.draft =
                "Replace every deprecated `onChange(of:perform:)` in the app target, starting with this one. Same behavior, nothing else changed."
            entry.context = .init(
                source: "Queue follow-ups while a turn runs · build output",
                text: "warning: 'onChange(of:perform:)' was deprecated in macOS 14.0  SessionView.swift:212")
        }
        switch state {
        case .failure:
            entry.failure = "The project folder is unavailable. Choose another project or restore the folder."
        case .offline:
            entry.device = .remote(RemoteHostID())
        case .devices: entry.picker = .device
        case .agents: entry.picker = .agent
        case .projects: entry.picker = .project
        default: break
        }
        return model
    }
}

struct QuickEntryPreviewFixture: View {
    let state: QuickEntryPreviewFixtures.State

    var body: some View {
        DSPreviewPair {
            let model = QuickEntryPreviewFixtures.model(state)
            QuickEntryPanel(model: model, entry: model.quickEntry, branch: "main")
                .frame(width: state == .narrow ? 380 : DS.QuickEntry.width)
                .padding(DS.Space.xl)
        }
    }
}
#endif
