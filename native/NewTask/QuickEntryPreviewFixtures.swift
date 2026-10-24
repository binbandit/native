#if DEBUG
import Foundation
import NativeHostProtocol
import SwiftUI

enum QuickEntryPreviewFixtures {
    enum State: String {
        case empty, selection, firstLaunch, failure, offline, narrow, devices, agents, projects
    }

    /// The isolated app can render the same states as #Preview without contacting a paired host.
    static func applyLaunchState(to model: AppModel) {
        guard let raw = UserDefaults.standard.string(forKey: "quickEntryFixture"), let state = State(rawValue: raw)
        else {
            return
        }
        configure(model.quickEntry, for: state)
    }

    static func model(_ state: State) -> AppModel {
        let model = AppModel.preview(state == .firstLaunch ? .empty : .populated)
        let entry = model.quickEntry
        entry.isPresented = true
        entry.project = model.previewProject()?.id
        entry.agent = model.agents.first?.agent.id
        configure(entry, for: state)
        return model
    }

    private static func configure(_ entry: QuickEntryModel, for state: State) {
        entry.draft = ""
        entry.context = nil
        entry.picker = nil
        entry.failure = nil
        entry.previewDeviceOptions = nil
        if state == .firstLaunch {
            entry.project = nil
            entry.agent = nil
        }
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
            entry.agent = nil
        case .devices:
            entry.picker = .device
            entry.previewDeviceOptions = [
                .init(device: .thisMac, name: "This Mac", availability: .online, checkout: .present(path: "native")),
                .init(
                    device: .remote(RemoteHostID()), name: "elara", availability: .online,
                    checkout: .present(path: "native")),
                .init(
                    device: .remote(RemoteHostID()), name: "build-box",
                    availability: .offline(reason: "Offline. Your draft stays here until the device is available."),
                    checkout: .present(path: "native")),
            ]
        case .agents: entry.picker = .agent
        case .projects: entry.picker = .project
        default: break
        }
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
