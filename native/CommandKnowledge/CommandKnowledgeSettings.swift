import ApprovalAnalysis
import SwiftUI

/// Local diagnostics and their privacy controls share one surface. Nothing here enters an export.
struct CommandKnowledgeSettings: View {
    var center: CommandKnowledgeCenter = .shared
    var problems: [String] = []

    var body: some View {
        SettingsSubheading("Command diagnostics")
        SettingsRowGroup {
            SettingsRow(
                "Count unknown programs locally",
                description: Text(
                    "Keeps program names and counts on this device. No arguments or paths. Never sent anywhere."),
                detail: Text(
                    center.isAllowed
                        ? "Only while Fine print is on. Turning this off keeps existing counts."
                        : "\(PolicyCenter.organizationSubject) has turned counting off.")
            ) {
                SettingsSwitch(
                    "Count unknown programs locally",
                    isOn: Binding(get: { center.isAllowed && center.userEnabled }, set: center.setEnabled))
            }
            .settingsLocked(center.isAllowed ? nil : PolicyCenter.managedExplanation)
            SettingsRow(
                "Unknown program counts",
                description: Text("Clear the local file at any time, including when counting is off.")
            ) {
                Button("Clear Counts") { Task { await center.clear() } }
                    .buttonStyle(.settings)
            }
        }
        SettingsNote("Most common unknown programs", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                if !center.hasLoaded {
                    Text("Reading local counts...")
                } else if center.entries.isEmpty {
                    Text(
                        "No unknown programs counted. Names appear after an unsupported program asks for approval while counting is on."
                    )
                } else {
                    ForEach(center.entries) { entry in
                        HStack {
                            Text(entry.program).font(.dsMono)
                            Spacer()
                            Text("\(entry.count)").monospacedDigit()
                        }
                    }
                    Text(
                        "Top ten on this device. Repeated updates to one request count once while the session is loaded."
                    )
                }
                if let message = center.message { Text(message) }
            }
        }
        .task { await center.refresh() }
        if !problems.isEmpty {
            SettingsNote("Some command knowledge was ignored", systemImage: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in Text(problem) }
                    Text(
                        "Correct the plugin document or managed policy, then reload the plugin or policy. Approvals still work."
                    )
                }
            }
        }
    }
}

#if DEBUG
#Preview("Command diagnostics - Empty") {
    DSPreviewPair {
        SettingsPage {
            CommandKnowledgeSettings(center: CommandKnowledgeCenter(url: nil, defaults: PreviewUserDefaults()))
        }.settingsPreviewPage()
    }.environment(PolicyCenter.shared)
}

#Preview("Command diagnostics - Counts and invalid entry") {
    DSPreviewPair {
        SettingsPage {
            CommandKnowledgeSettings(
                center: CommandKnowledgeCenter(
                    url: nil, defaults: PreviewUserDefaults(),
                    entries: [
                        .init(program: "internal-release-tool", count: 42), .init(program: "schema-check", count: 7),
                    ]), problems: ["Plugin example: program 2 has an invalid template; ignored."])
        }.settingsPreviewPage()
    }.environment(PolicyCenter.shared)
}
#Preview("Command diagnostics - Storage error and narrow") {
    DSPreviewPair {
        SettingsPage {
            CommandKnowledgeSettings(
                center: CommandKnowledgeCenter(
                    url: nil, defaults: PreviewUserDefaults(),
                    message: "Command counts are damaged. Clear the counts in Settings to start again."))
        }.settingsPreviewPage(width: 360)
    }.environment(PolicyCenter.shared)
}

#Preview("Command diagnostics - Loading") {
    DSPreviewPair {
        SettingsPage {
            CommandKnowledgeSettings(
                center: CommandKnowledgeCenter(
                    url: nil, defaults: PreviewUserDefaults(), hasLoaded: false))
        }.settingsPreviewPage()
    }.environment(PolicyCenter.shared)
}
#endif
