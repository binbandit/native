import Experiments
import SwiftUI

/// One heading's worth of Labs: Native's own experiments, or one plugin's with its problems.
struct LabsSection: Identifiable {
    let id: String
    /// Nil for Native's own.
    let pluginName: String?
    let experiments: [ExperimentDescriptor]
    let problems: [PluginExperimentProblem]

    /// Native first, then plugins in the order they load; a plugin whose experiments all have
    /// problems still gets a section, so its author sees why.
    static func sections(catalog: ExperimentCatalog, problems: [PluginExperimentProblem]) -> [LabsSection] {
        var sections = catalog.groups.map { group in
            switch group.origin {
            case .native:
                LabsSection(id: group.id, pluginName: nil, experiments: group.experiments, problems: [])
            case .plugin(let pluginID, let name):
                LabsSection(
                    id: group.id, pluginName: name, experiments: group.experiments,
                    problems: problems.filter { $0.pluginID == pluginID }
                )
            }
        }
        let shown = Set(catalog.groups.compactMap { if case .plugin(let id, _) = $0.origin { id } else { nil } })
        var unlisted: [String] = []
        for problem in problems where !shown.contains(problem.pluginID) && !unlisted.contains(problem.pluginID) {
            unlisted.append(problem.pluginID)
        }
        sections += unlisted.map { pluginID in
            let problems = problems.filter { $0.pluginID == pluginID }
            return LabsSection(
                id: "plugin.\(pluginID)", pluginName: problems.first?.pluginName, experiments: [], problems: problems
            )
        }
        return sections
    }
}

/// An experiment a plugin declares that Labs can't offer, and why.
struct LabsProblemRow: View {
    let problem: PluginExperimentProblem

    var body: some View {
        SettingsRow(
            title: Text(verbatim: problem.problem.experiment ?? "experiments"),
            description: Text(problem.problem.message),
            accessory: { SettingsBadge("Not loaded") },
            control: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.dsWarning)
                    .accessibilityLabel("Problem")
            }
        )
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Labs problem") {
    DSPreviewPair {
        SettingsRowGroup {
            LabsProblemRow(problem: LabsPreviewFixtures.problem)
        }
        .settingsPreviewPage()
    }
}
#endif
